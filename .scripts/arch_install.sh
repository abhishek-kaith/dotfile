#!/usr/bin/env bash
set -euo pipefail
# Arch Linux Automated Installer (Zen + UKI + LUKS2 + Btrfs)
# Refrence: https://wiki.archlinux.org/title/User:Bai-Chiang/Arch_Linux_installation_with_unified_kernel_image_(UKI),_full_disk_encryption,_secure_boot,_btrfs_snapshots,_and_common_setups

default_user="arch"
default_hostname="archbox"
boot_label="EFI"
root_label="LINUX"
crypt_name="cryptroot"

error_exit() { 
    echo "============================================" >&2
    echo "[ERROR] $1" >&2
    echo "============================================" >&2
    exit 1
}
info() { echo "[INFO] $1"; }

comment_if_exact() {
    local file="$1"
    local pattern="$2"
    # Escape any sed special characters in pattern
    local escaped_pattern
    escaped_pattern=$(printf '%s\n' "$pattern" | sed 's/[&/\]/\\&/g')
    # Comment the line if it exactly matches (ignoring leading spaces)
    sed -i "s/^[[:space:]]*$escaped_pattern/# $pattern/" "$file"
}

uncomment_if_exact() {
    local file="$1"
    local pattern="$2"
    local escaped_pattern
    escaped_pattern=$(printf '%s\n' "$pattern" | sed 's/[&/\]/\\&/g')
    # Uncomment the line if it starts with optional # and spaces
    sed -i "s/^[[:space:]]*#*[[:space:]]*$escaped_pattern/$pattern/" "$file"
}

uncomment_if_commented_key() {
    local file="$1"
    local key="$2"
    # Match commented key lines like "# key=" and uncomment them
    sed -i "s/^[[:space:]]*#*[[:space:]]*\(${key}=\)/\1/" "$file"
}

check_root() { 
    if (( EUID != 0 )); then
        error_exit "Run as root!"
    fi
}

check_uefi() {
    info "Checking UEFI boot mode..."
    [[ -d /sys/firmware/efi ]] || error_exit "System not booted in UEFI mode."
    uefi_code=$(< /sys/firmware/efi/fw_platform_size 2>/dev/null || echo "")
    info "UEFI detected: ${uefi_code:-UEFI}-bit"
}

select_device() {
    info "Available disks:"
    lsblk -dno NAME,SIZE,MODEL
    read -rp "Enter device to partition (e.g., sda or nvme0n1): " dev
    [[ $dev == /dev/* ]] && device="$dev" || device="/dev/$dev"
    [[ -b $device ]] || error_exit "Invalid device: $device"

    echo "Selected device: $device"
    read -rp "This will ERASE ALL DATA on $device. Continue? (yes/no): " confirm
    [[ "${confirm,,}" == "yes" ]] || error_exit "Aborted by user."
}

get_part_suffix() {
    local base; base=$(basename "$device")
    [[ $base =~ ^nvme ]] || [[ $base =~ ^mmcblk ]] && echo "p" || echo ""
}

create_partitions() {
    read -rp "Enter size for main partition (e.g., 50G, Enter=all remaining): " mainsize
    mainsize="${mainsize:-}"

    info "Wiping partition table..."
    sgdisk -Z "$device"

    info "Creating 1GiB EFI partition..."
    sgdisk -n 1:0:+1G -t 1:ef00 -c 1:"$boot_label" "$device"

    if [[ -n "$mainsize" ]]; then
        info "Creating main partition ($mainsize)..."
        sgdisk -n 2:0:+${mainsize} -t 2:8300 -c 2:"$root_label" "$device"
    else
        info "Creating main partition with remaining space..."
        sgdisk -n 2:0:0 -t 2:8300 -c 2:"$root_label" "$device"
    fi

    local suffix; suffix=$(get_part_suffix)
    boot_partition="${device}${suffix}1"
    main_partition="${device}${suffix}2"

    info "Partitions created: EFI -> $boot_partition, ROOT -> $main_partition"
}

setup_encryption() {
    info "Setting up LUKS2 encryption..."
    [[ -b "/dev/mapper/$crypt_name" ]] && cryptsetup close "$crypt_name" || true
    sector_size=$(lsblk -no PHY-SEC "$main_partition" 2>/dev/null || echo 512)
    cryptsetup --type luks2 --verify-passphrase --sector-size "$sector_size" luksFormat "$main_partition"
    cryptsetup open "$main_partition" "$crypt_name"
    info "LUKS container opened at /dev/mapper/$crypt_name"
}

format_partitions() {
    info "Formatting partitions..."
    mkfs.fat -F32 "$boot_partition"
    mkfs.btrfs -f "/dev/mapper/$crypt_name"
}

create_subvolumes() {
    info "Creating Btrfs subvolumes..."
    mount "/dev/mapper/$crypt_name" /mnt

    # Create main subvolumes including swap
    for subvol in @ @home @snapshots @var_log @var_cache @swap; do
        btrfs subvolume create "/mnt/$subvol"
    done

    # Create standard directories
    mkdir -p /mnt/{home,.snapshots,var/log,var/cache,swap}
    chmod 700 /mnt/.snapshots

    umount /mnt
}

mount_subvolumes() {
    info "Mounting subvolumes..."
    local opts="ssd,noatime,compress=zstd:1,space_cache=v2,autodefrag"

    # Root
    mount -o $opts,subvol=@ /dev/mapper/$crypt_name /mnt
    mkdir -p /mnt/{home,.snapshots,var/log,var/cache,swap}

    # Other subvolumes
    mount -o $opts,subvol=@home,nodev /dev/mapper/$crypt_name /mnt/home
    mount -o $opts,subvol=@snapshots,nodev,nosuid,noexec /dev/mapper/$crypt_name /mnt/.snapshots
    mount -o $opts,subvol=@var_log,nodev,nosuid,noexec /dev/mapper/$crypt_name /mnt/var/log
    mount -o $opts,subvol=@var_cache,nodev,nosuid,noexec /dev/mapper/$crypt_name /mnt/var/cache
    mount -o $opts,subvol=@swap,nodev,nosuid,noexec /dev/mapper/$crypt_name /mnt/swap

    # EFI
    mkdir -p /mnt/efi
    mount "$boot_partition" /mnt/efi || error_exit "Failed to mount EFI"
}

create_btrfs_swap() {
    info "Creating Btrfs swap file..."
    local swapfile="/mnt/swap/swapfile"
    mkdir -p "$(dirname "$swapfile")"
    local ram_size_mb=$(grep MemTotal /proc/meminfo | awk '{print int($2/1024)}')
    local swap_size_mb=$((ram_size_mb + 1024))  # +1GB for hibernation safety
    info "RAM detected: ${ram_size_mb}MB, creating swap file of ${swap_size_mb}MB."
    btrfs filesystem mkswapfile --size "${swap_size_mb}M" "$swapfile"
    chmod 600 "$swapfile"
    swapon "$swapfile"
    info "Btrfs swap file created and enabled."
}

select_microcode() {
    info "Select CPU microcode:"
    echo "1) AMD  2) Intel  3) None"
    read -rp "Choice [1-3]: " mc
    case "$mc" in
        1) microcode_pkg="amd-ucode" ;;
        2) microcode_pkg="intel-ucode" ;;
        3) microcode_pkg="" ;;
        *) error_exit "Invalid choice." ;;
    esac
    info "Selected microcode: ${microcode_pkg:-None}"
}

install_base_system() {
    info "Installing base system..."
    local packages=(base base-devel linux-zen linux-zen-headers linux-firmware btrfs-progs efibootmgr networkmanager terminus-font neovim sbctl openssh)
    select_microcode
    [[ -n "$microcode_pkg" ]] && packages+=("$microcode_pkg")
    pacstrap -K /mnt "${packages[@]}"
}

generate_fstab() {
    info "Generating fstab..."
    genfstab -U /mnt >> /mnt/etc/fstab
    sed -i 's/subvolid=[0-9]*,//g' /mnt/etc/fstab || true
}

configure_system() {
    info "Configuring system basics..."
    read -rp "Hostname [${default_hostname}]: " input_hostname
    hostname="${input_hostname:-$default_hostname}"
    echo "$hostname" > /mnt/etc/hostname

    cat <<EOF > /mnt/etc/vconsole.conf
KEYMAP=us
FONT=ter-128b
EOF

    arch-chroot /mnt sed -i -e '/^#en_US.UTF-8 UTF-8/s/^#//' /etc/locale.gen
    arch-chroot /mnt locale-gen
    echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf
    arch-chroot /mnt ln -sf /usr/share/zoneinfo/UTC /etc/localtime
    arch-chroot /mnt hwclock --systohc

    read -rp "Username [${default_user}]: " input_user
    user="${input_user:-$default_user}"
    arch-chroot /mnt useradd -G wheel -m "$user"
    echo "Set password for $user (in chroot)..."
    arch-chroot /mnt passwd "$user"

    echo "Set password for Root (in chroot)..."
    arch-chroot /mnt passwd

    cat <<EOF > /mnt/etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${hostname}.localdomain   ${hostname}
EOF

    sed -i 's/^HOOKS=.*/HOOKS=(base systemd autodetect keyboard keymap sd-vconsole block sd-encrypt filesystems resume fsck)/' /mnt/etc/mkinitcpio.conf

    luks_uuid=$(blkid -s UUID -o value "$main_partition")
    echo "${crypt_name} UUID=${luks_uuid} - password-echo=no,x-systemd.device-timeout=0,timeout=0,no-read-workqueue,no-write-workqueue,discard" > /mnt/etc/crypttab.initramfs

    resume_offset=$(btrfs inspect-internal map-swapfile -r /mnt/swap/swapfile)
    echo "root=/dev/mapper/${crypt_name} rootfstype=btrfs rootflags=subvol=/@ rw mem_sleep_default=deep resume=/swap/swapfile resume_offset=$resume_offset modprobe.blacklist=pcspkr quiet loglevel=3" > /mnt/etc/kernel/cmdline
    echo "root=/dev/mapper/${crypt_name} rootfstype=btrfs rootflags=subvol=/@ rw mem_sleep_default=deep resume=/swap/swapfile resume_offset=$resume_offset modprobe.blacklist=pcspkr" > /mnt/etc/kernel/cmdline_fallback

    for preset in /mnt/etc/mkinitcpio.d/*.preset; do
        comment_if_exact "$preset" "PRESETS=('default')"
        uncomment_if_exact "$preset" "PRESETS=('default' 'fallback')"
        for key in default_uki fallback_uki default_image fallback_image default_options fallback_options; do
            uncomment_if_commented_key "$preset" "$key"
        done
    done

    arch-chroot /mnt mkdir -p /efi/EFI/Linux
    arch-chroot /mnt mkinitcpio -P
    arch-chroot /mnt systemctl enable NetworkManager
    arch-chroot /mnt sbctl create-keys || true
    arch-chroot /mnt chattr -i /sys/firmware/efi/efivars/* || true
    arch-chroot /mnt sbctl enroll-keys --microsoft || true
}

install_bootloader() {
    info "Creating UEFI boot entries..."
    local efi_disk efi_part_num
    efi_disk=$(lsblk -npo PKNAME "$boot_partition" | head -1)
    efi_part_num=$(lsblk -npo PARTN "$boot_partition" | head -1)

    local kernels=()
    for k in linux linux-lts linux-zen linux-hardened; do
        arch-chroot /mnt pacman -Q $k &>/dev/null && kernels+=("$k") || true
    done

    if [[ ${#kernels[@]} -eq 0 ]]; then
        info "No kernels detected, skipping efibootmgr entries."
        return
    fi

    for kernel in "${kernels[@]}"; do
        arch-chroot /mnt sbctl sign --save /efi/EFI/Linux/arch-${kernel}.efi
        arch-chroot /mnt sbctl sign --save /efi/EFI/Linux/arch-${kernel}-fallback.efi

        arch-chroot /mnt efibootmgr --create --disk ${efi_disk} --part ${efi_part_num} \
            --label "ArchLinux-${kernel}" --loader "EFI\\Linux\\arch-${kernel}.efi" --unicode
        arch-chroot /mnt efibootmgr --create --disk ${efi_disk} --part ${efi_part_num} \
            --label "ArchLinux-${kernel}-fallback" --loader "EFI\\Linux\\arch-${kernel}-fallback.efi" --unicode
    done

    info "Current EFI boot entries:"
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
