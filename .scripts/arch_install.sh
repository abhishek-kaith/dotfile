#!/bin/bash
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

info() {
    echo "$1"
}

check_uefi() {
    info "Checking UEFI..."
    if [[ ! -f /sys/firmware/efi/fw_platform_size ]]; then
        error_exit "System not booted in UEFI mode."
    fi
    local uefi_code
    uefi_code=$(< /sys/firmware/efi/fw_platform_size)
    echo "UEFI detected: ${uefi_code}-bit"
}

select_device() {
    info "Available disks:"
    lsblk -dno NAME,SIZE,MODEL || error_exit "Failed to list disks."
    read -rp "Enter the device to partition (e.g., sda): " dev
    device="/dev/$dev"
    [[ -b $device ]] || error_exit "Invalid device: $device"

    echo "Selected device: $device"
    read -rp "This will ERASE ALL DATA on $device. Continue? (yes/no): " confirm
    confirm=$(echo "$confirm" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
    [[ "$confirm" == "yes" ]] || error_exit "Aborted by user."
}

create_partitions() {
    read -rp "Enter size for main partition (optional, e.g., 50G, press Enter for all remaining): " mainsize
    mainsize="${mainsize:-}"

    info "Wiping existing partition table..."
    sgdisk -Z "$device" || error_exit "Failed to wipe $device"

    info "Creating 1GB EFI partition..."
    sgdisk -n 1:0:+1G -t 1:ef00 -c 1:"$boot_label" "$device" || error_exit "Failed to create EFI partition"
    boot_partition="${device}1"

    if [[ -n "$mainsize" ]]; then
        info "Creating main partition of size $mainsize..."
        sgdisk -n 2:0:+${mainsize} -t 2:8300 -c 2:"$root_label" "$device"
    else
        info "Creating main partition with remaining space..."
        sgdisk -n 2:0:0 -t 2:8300 -c 2:"$root_label" "$device"
    fi
    main_partition="${device}2"
}

setup_encryption() {
    info "Setting up LUKS encryption..."
    if [[ -b "/dev/mapper/$crypt_name" ]]; then
        info "Closing existing LUKS mapping..."
        cryptsetup close "$crypt_name"
    fi

    local sector_size
    sector_size=$(lsblk -no PHY-SEC "$main_partition" 2>/dev/null || echo 512)

    cryptsetup --type luks2 --verify-passphrase \
        --sector-size "$sector_size" --verbose \
        luksFormat "$main_partition" || error_exit "Failed to format with LUKS"

    cryptsetup open "$main_partition" "$crypt_name" || error_exit "Failed to open LUKS container"
}

format_partitions() {
    info "Formatting partitions..."
    mkfs.fat -F32 "$boot_partition" || error_exit "Failed to format EFI partition"
    mkfs.btrfs "/dev/mapper/$crypt_name" || error_exit "Failed to format root partition"
}

create_subvolumes() {
    info "Creating Btrfs subvolumes..."
    mount "/dev/mapper/$crypt_name" /mnt || error_exit "Failed to mount root partition"

    for subvol in @ @home @snapshots @var_log @var_cache; do
        btrfs subvolume create "/mnt/$subvol" || error_exit "Failed to create subvolume $subvol"
    done

    mkdir -p /mnt/@/{home,.snapshots,efi,var/log,var/cache}
    umount -R /mnt || error_exit "Failed to unmount root partition"
}

mount_subvolumes() {
    info "Mounting subvolumes..."
    local cryptdev="/dev/mapper/$crypt_name"

    mount -o ssd,noatime,compress=zstd:1,space_cache=v2,autodefrag,subvol=@ "$cryptdev" /mnt
    mount -o ssd,noatime,compress=zstd:1,space_cache=v2,autodefrag,subvol=@home,nodev "$cryptdev" /mnt/home
    mount -o ssd,noatime,compress=zstd:1,space_cache=v2,autodefrag,subvol=@snapshots,nodev,nosuid,noexec "$cryptdev" /mnt/.snapshots
    mount -o ssd,noatime,compress=zstd:1,space_cache=v2,autodefrag,subvol=@var_log,nodev,nosuid,noexec "$cryptdev" /mnt/var/log
    mount -o ssd,noatime,compress=zstd:1,space_cache=v2,autodefrag,subvol=@var_cache,nodev,nosuid,noexec "$cryptdev" /mnt/var/cache

    mount "$boot_partition" /mnt/efi || error_exit "Failed to mount EFI"
    info "All subvolumes and EFI partition mounted successfully."
}

install_base_system() {
    info "Installing base system..."
    pacstrap -K /mnt base base-devel linux-zen linux-zen-headers linux-firmware btrfs-progs efibootmgr networkmanager terminus-font neovim sbctl openssh
}

generate_fstab() {
    info "Generating fstab..."
    genfstab -U /mnt >> /mnt/etc/fstab
    sed -i 's/subvolid=[0-9]*,//g' /mnt/etc/fstab
}

configure_system() {
    info "Configuring system basics..."

    read -rp "Enter hostname (default: $default_hostname): " input_hostname
    hostname="${input_hostname:-$default_hostname}"
    echo "$hostname" > /mnt/etc/hostname
    info "Hostname set to: $hostname"

    info "Running systemd-firstboot..."
    systemd-firstboot --root /mnt --locale=en_US.UTF-8 --timezone=UTC --hostname="$hostname" --prompt-root-password

    hwclock --systohc

    info "Setting locale..."
    sed -i -e '/^#en_US.UTF-8 UTF-8/s/^#//' /mnt/etc/locale.gen
    arch-chroot /mnt locale-gen
    echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf

    read -rp "Enter username (default: $default_user): " input_user
    user="${input_user:-$default_user}"

    info "Creating user '$user' and enabling sudo..."
    arch-chroot /mnt useradd -G wheel -m "$user"
    arch-chroot /mnt passwd "$user"

    info "Setting up /etc/hosts..."
    cat <<EOF > /mnt/etc/vconsole.conf
KEYMAP=us
FONT=ter-128b
EOF
    cat <<EOF > /mnt/etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${hostname}.localdomain   ${hostname}
EOF
    info "Configuring mkinitcpio for unified kernel..."
    sed -i 's/^HOOKS=(.*)/HOOKS=(base systemd autodetect microcode modconf kms keyboard keymap sd-vconsole block sd-encrypt filesystems fsck)/' /mnt/etc/mkinitcpio.conf

    local luks_uuid
    luks_uuid=$(blkid -s UUID -o value "$main_partition")
    [[ -n "$luks_uuid" ]] || error_exit "Failed to get UUID for $main_partition"
    cat <<EOF > /mnt/etc/crypttab.initramfs
cryptroot  UUID=${luks_uuid}  -  password-echo=no,x-systemd.device-timeout=0,timeout=0,no-read-workqueue,no-write-workqueue,discard
EOF

    echo "root=/dev/mapper/$crypt_name rootfstype=btrfs rootflags=subvol=/@ rw modprobe.blacklist=pcspkr zswap.enabled=0" > /mnt/etc/kernel/cmdline

    info "Modifying all *.preset files to enable UKIs..."
    for preset in /mnt/etc/mkinitcpio.d/*.preset; do
      sed -i -E 's/^(default_image=)/#\1/' "$preset"
      sed -i -E 's/^(fallback_image=)/#\1/' "$preset"
      sed -i -E 's/^#(default_uki=)/\1/' "$preset"
      sed -i -E 's/^#(fallback_uki=)/\1/' "$preset"
    done

    info "All preset files updated: images commented out, UKIs enabled."
    mkdir -p /mnt/efi/EFI/Linux
    arch-chroot /mnt mkinitcpio -P
    info "Root Password"
    arch-chroot /mnt passwd
    info "Enable System Services"
    arch-chroot /mnt systemctl enable NetworkManager
    arch-chroot /mnt sbctl create-keys
    arch-chroot /mnt sbctl enroll-keys --microsoft

    for efi in /mnt/efi/EFI/Linux/*.efi; do
      [ -f "$efi" ] || continue
      echo "Signing ${efi#/mnt}..."
      arch-chroot /mnt sbctl sign --save "${efi#/mnt}"
    done
}

install_bootloader() {
    info "Setting up UEFI boot entries..."
    local efi_disk efi_part_num
    efi_disk=$(lsblk -npo PKNAME "$boot_partition" | head -1)
    efi_part_num=$(lsblk -npo PARTN "$boot_partition" | head -1)
    info "EFI disk: $efi_disk"
    info "EFI partition number: $efi_part_num"

    local kernels=()
    if arch-chroot /mnt pacman -Q linux &>/dev/null; then
        kernels+=("linux")
    fi
    if arch-chroot /mnt pacman -Q linux-lts &>/dev/null; then
        kernels+=("linux-lts")
    fi
    if arch-chroot /mnt pacman -Q linux-zen &>/dev/null; then
        kernels+=("linux-zen")
    fi
    if arch-chroot /mnt pacman -Q linux-hardened &>/dev/null; then
        kernels+=("linux-hardened")
    fi
    if [[ ${#kernels[@]} -eq 0 ]]; then
        error_exit "No kernel packages detected!"
    fi
    info "Detected kernels: ${kernels[*]}"

    for kernel in "${kernels[@]}"; do
        info "Creating boot entries for $kernel..."
        arch-chroot /mnt efibootmgr --create \
            --disk "$efi_disk" \
            --part "$efi_part_num" \
            --label "ArchLinux-$kernel-fallback" \
            --loader "EFI\\Linux\\arch-$kernel-fallback.efi" \
            --unicode || info "Warning: Failed to create fallback boot entry for $kernel"

        arch-chroot /mnt efibootmgr --create \
            --disk "$efi_disk" \
            --part "$efi_part_num" \
            --label "ArchLinux-$kernel" \
            --loader "EFI\\Linux\\arch-$kernel.efi" \
            --unicode || info "Warning: Failed to create boot entry for $kernel"
    done
    info "UEFI boot entries created successfully."
    info "Current boot order:"
    arch-chroot /mnt efibootmgr
}

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
