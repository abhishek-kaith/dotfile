#!/usr/bin/env bash
set -euo pipefail

default_user="arch"
default_hostname="archbox"
boot_label="BOOT"
root_label="LINUX"
crypt_name="cryptroot"

error_exit() {
    echo "ERROR: $1" >&2
    exit 1
}
info() { echo "[INFO] $1"; }

check_root() {
    if (( EUID != 0 )); then
        error_exit "This script must be run as root."
    fi
}

check_uefi() {
    info "Checking UEFI..."
    if [[ ! -d /sys/firmware/efi ]]; then
        error_exit "System not booted in UEFI mode."
    fi
    if [[ -f /sys/firmware/efi/fw_platform_size ]]; then
        uefi_code=$(< /sys/firmware/efi/fw_platform_size)
        info "UEFI detected: ${uefi_code}-bit"
    else
        info "UEFI detected."
    fi
}

select_device() {
    info "Available disks:"
    lsblk -dno NAME,SIZE,MODEL || error_exit "Failed to list disks."
    read -rp "Enter the device to partition (e.g., sda or nvme0n1): " dev
    # accept full path or basename
    if [[ $dev == /dev/* ]]; then
        device="$dev"
    else
        device="/dev/$dev"
    fi
    [[ -b $device ]] || error_exit "Invalid device: $device"

    echo "Selected device: $device"
    read -rp "This will ERASE ALL DATA on $device. Continue? (yes/no): " confirm
    confirm=$(echo "$confirm" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
    [[ "$confirm" == "yes" ]] || error_exit "Aborted by user."
}

get_part_suffix() {
    local base
    base=$(basename "$device")
    if [[ $base =~ ^nvme ]] || [[ $base =~ ^mmcblk ]]; then
        echo "p"
    else
        echo ""
    fi
}

create_partitions() {
    read -rp "Enter size for main partition (optional, e.g., 50G, press Enter for all remaining): " mainsize
    mainsize="${mainsize:-}"

    info "Wiping existing partition table..."
    sgdisk -Z "$device" || error_exit "Failed to wipe partition table on $device"

    info "Creating 1GiB EFI partition..."
    sgdisk -n 1:0:+1G -t 1:ef00 -c 1:"$boot_label" "$device" || error_exit "Failed to create EFI partition"

    if [[ -n "$mainsize" ]]; then
        info "Creating main partition of size $mainsize..."
        sgdisk -n 2:0:+${mainsize} -t 2:8300 -c 2:"$root_label" "$device" || error_exit "Failed to create main partition"
    else
        info "Creating main partition using remaining space..."
        sgdisk -n 2:0:0 -t 2:8300 -c 2:"$root_label" "$device" || error_exit "Failed to create main partition"
    fi

    local suffix
    suffix=$(get_part_suffix)
    boot_partition="${device}${suffix}1"
    main_partition="${device}${suffix}2"

    info "Partitions created: EFI -> $boot_partition  ROOT -> $main_partition"
}

setup_encryption() {
    info "Setting up LUKS2 encryption on $main_partition..."

    if [[ -b "/dev/mapper/$crypt_name" ]]; then
        info "Closing existing LUKS mapping..."
        cryptsetup close "$crypt_name" || true
    fi

    # best-effort sector size detection
    local sector_size
    sector_size=$(lsblk -no PHY-SEC "$main_partition" 2>/dev/null || echo 512)

    # prompt for passphrase interactively (cryptsetup will prompt)
    cryptsetup --type luks2 --verify-passphrase --sector-size "$sector_size" luksFormat "$main_partition" || error_exit "luksFormat failed"
    cryptsetup open "$main_partition" "$crypt_name" || error_exit "Failed to open LUKS container"
    info "LUKS container opened at /dev/mapper/$crypt_name"
}

format_partitions() {
    info "Formatting partitions..."
    mkfs.fat -F32 "$boot_partition" || error_exit "Failed to format EFI partition $boot_partition"
    mkfs.btrfs -f "/dev/mapper/$crypt_name" || error_exit "Failed to format root partition as btrfs"
}

create_subvolumes() {
    info "Creating Btrfs subvolumes..."
    mount "/dev/mapper/$crypt_name" /mnt || error_exit "Failed to mount root partition on /mnt"
    for subvol in @ @home @snapshots @var_log @var_cache; do
        btrfs subvolume create "/mnt/$subvol" || error_exit "Failed to create subvolume $subvol"
    done
    mkdir -p /mnt/{home,.snapshots,var/log,var/cache,boot}
    umount /mnt || error_exit "Failed to unmount /mnt after subvolume creation"
    info "Subvolumes created and /mnt unmounted"
}

mount_subvolumes() {
    info "Mounting subvolumes with recommended options..."
    local cryptdev="/dev/mapper/$crypt_name"

    mount -o ssd,noatime,compress=zstd:1,space_cache=v2,autodefrag,subvol=@ "$cryptdev" /mnt
    mkdir -p /mnt/{home,.snapshots,var/log,var/cache}
    mount -o ssd,noatime,compress=zstd:1,space_cache=v2,autodefrag,subvol=@home,nodev "$cryptdev" /mnt/home
    mount -o ssd,noatime,compress=zstd:1,space_cache=v2,autodefrag,subvol=@snapshots,nodev,nosuid,noexec "$cryptdev" /mnt/.snapshots
    mount -o ssd,noatime,compress=zstd:1,space_cache=v2,autodefrag,subvol=@var_log,nodev,nosuid,noexec "$cryptdev" /mnt/var/log
    mount -o ssd,noatime,compress=zstd:1,space_cache=v2,autodefrag,subvol=@var_cache,nodev,nosuid,noexec "$cryptdev" /mnt/var/cache

    mkdir -p /mnt/boot
    mount "$boot_partition" /mnt/boot || error_exit "Failed to mount EFI partition $boot_partition to /mnt/boot"
    info "All subvolumes and EFI partition mounted successfully."
}


select_microcode() {
    info "Select CPU microcode:"
    echo "1) AMD"
    echo "2) Intel"
    echo "3) None"
    read -rp "Enter choice [1-3]: " mc

    case "$mc" in
        1)
            microcode_pkg="amd-ucode"
            ;;
        2)
            microcode_pkg="intel-ucode"
            ;;
        3)
            microcode_pkg=""
            ;;
        *)
            error_exit "Invalid microcode selection."
            ;;
    esac

    if [[ -n "$microcode_pkg" ]]; then
        info "Selected microcode: $microcode_pkg"
    else
        info "No microcode will be installed."
    fi
}


install_base_system() {
    info "Installing base system..."
    local packages=(
        base base-devel
        linux-zen linux-zen-headers
        linux-firmware
        btrfs-progs
        efibootmgr
        networkmanager
        terminus-font
        neovim
        sbctl
        openssh
    )
    select_microcode
    if [[ -n "$microcode_pkg" ]]; then
        packages+=("$microcode_pkg")
    fi

    pacstrap -K /mnt "${packages[@]}"
}

generate_fstab() {
    info "Generating /etc/fstab..."
    genfstab -U /mnt >> /mnt/etc/fstab
    # remove subvolid tokens if present (optional)
    sed -i 's/subvolid=[0-9]*,//g' /mnt/etc/fstab || true
}

configure_system() {
    info "Configuring system basics..."

    read -rp "Enter hostname (default: $default_hostname): " input_hostname
    hostname="${input_hostname:-$default_hostname}"
    echo "$hostname" > /mnt/etc/hostname
    info "Hostname set to: $hostname"

    info "Creating vconsole config..."
    cat <<EOF > /mnt/etc/vconsole.conf
KEYMAP=us
FONT=ter-128b
EOF

    info "Setting locale and timezone etc..."
    arch-chroot /mnt /bin/bash -c "sed -i -e '/^#en_US.UTF-8 UTF-8/s/^#//' /etc/locale.gen && locale-gen"
    echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf
    arch-chroot /mnt /bin/bash -c "ln -sf /usr/share/zoneinfo/UTC /etc/localtime && hwclock --systohc"

    read -rp "Enter username (default: $default_user): " input_user
    user="${input_user:-$default_user}"

    info "Creating user '$user' and enabling sudo..."
    arch-chroot /mnt useradd -G wheel -m "$user"
    echo "Set password for $user (in chroot)..."
    arch-chroot /mnt passwd "$user"

    info "Setting /etc/hosts..."
    cat <<EOF > /mnt/etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${hostname}.localdomain   ${hostname}
EOF

    # Configure mkinitcpio hooks for systemd + encryption + sd-vconsole
    info "Configuring mkinitcpio HOOKS for systemd + sd-encrypt..."
    if [[ -f /mnt/etc/mkinitcpio.conf ]]; then
        sed -i 's/^HOOKS=.*/HOOKS=(base systemd autodetect keyboard keymap sd-vconsole block sd-encrypt filesystems fsck)/' /mnt/etc/mkinitcpio.conf
    fi

    # Create /etc/crypttab for initramfs (use UUID of partition)
    luks_uuid=$(blkid -s UUID -o value "$main_partition" || true)
    if [[ -z "$luks_uuid" ]]; then
        error_exit "Failed to obtain UUID of $main_partition"
    fi
    mkdir -p /mnt/etc
    cat <<EOF > /mnt/etc/crypttab
${crypt_name} UUID=${luks_uuid} none luks,discard
EOF

    # create kernel cmdline file for UKI (if using UKI)
    mkdir -p /mnt/etc/kernel
    echo "root=/dev/mapper/${crypt_name} rootfstype=btrfs rootflags=subvol=/@ rw" > /mnt/etc/kernel/cmdline

    # enable necessary services and finalize initramfs (chroot)
    arch-chroot /mnt /bin/bash -c "mkinitcpio -P"
    arch-chroot /mnt /bin/bash -c "systemctl enable NetworkManager"
    arch-chroot /mnt /bin/bash -c "sbctl create-keys || true"
    arch-chroot /mnt /bin/bash -c "sbctl enroll-keys --microsoft || true"

    # Sign UKIs/EFI files if they exist (best-effort)
    if compgen -G "/mnt/boot/EFI/Linux/*.efi" >/dev/null; then
        for efi in /mnt/boot/EFI/Linux/*.efi; do
            [ -f "$efi" ] || continue
            info "Signing ${efi#/mnt}..."
            arch-chroot /mnt sbctl sign --save "${efi#/mnt}" || info "Signing failed for ${efi}"
        done
    fi
}

install_bootloader() {
    info "Setting up UEFI boot entries..."
    local efi_disk efi_part_num
    efi_disk=$(lsblk -npo PKNAME "$boot_partition" | head -1)
    efi_part_num=$(lsblk -npo PARTN "$boot_partition" | head -1)
    info "EFI disk: $efi_disk"
    info "EFI partition number: $efi_part_num"

    # detect installed kernels inside chroot
    local kernels=()
    if arch-chroot /mnt pacman -Q linux &>/dev/null; then kernels+=("linux"); fi
    if arch-chroot /mnt pacman -Q linux-lts &>/dev/null; then kernels+=("linux-lts"); fi
    if arch-chroot /mnt pacman -Q linux-zen &>/dev/null; then kernels+=("linux-zen"); fi
    if arch-chroot /mnt pacman -Q linux-hardened &>/dev/null; then kernels+=("linux-hardened"); fi

    if [[ ${#kernels[@]} -eq 0 ]]; then
        info "No kernel package detected in chroot. Skipping efibootmgr entries (you can create them after first boot)."
        return
    fi

    info "Detected kernels: ${kernels[*]}"
    for kernel in "${kernels[@]}"; do
        info "Creating UEFI boot entries for kernel: $kernel (best-effort)"
        arch-chroot /mnt /bin/bash -c "efibootmgr --create --disk ${efi_disk} --part ${efi_part_num} --label 'ArchLinux-${kernel}' --loader 'EFI\\Linux\\arch-${kernel}.efi' --unicode" || info "Warning: efibootmgr entry creation failed for ${kernel}"
        arch-chroot /mnt /bin/bash -c "efibootmgr --create --disk ${efi_disk} --part ${efi_part_num} --label 'ArchLinux-${kernel}-fallback' --loader 'EFI\\Linux\\arch-${kernel}-fallback.efi' --unicode" || info "Warning: efibootmgr fallback creation failed for ${kernel}"
    done

    info "Current efibootmgr output (chroot):"
    arch-chroot /mnt efibootmgr || true
}

check_root
check_uefi
select_device
create_partitions
setup_encryption
format_partitions
create_subvolumes
mount_subvolumes
install_base_system
generate_fstab
configure_system
install_bootloader

info "Installation base setup complete!"
