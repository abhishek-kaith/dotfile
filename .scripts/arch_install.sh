#!/usr/bin/env bash
set -euo pipefail

# Arch Linux Automated Installer (Zen + UKI + LUKS2 + Btrfs)
# Reference: https://wiki.archlinux.org/title/User:Bai-Chiang/...

DEFAULT_USER="arch"
DEFAULT_HOSTNAME="archbox"
BOOT_LABEL="EFI"
ROOT_LABEL="LINUX"
CRYPT_NAME="cryptroot"
BTRFS_OPTS="ssd,noatime,compress=zstd:1,space_cache=v2,autodefrag"

# Pre-flight Checks
echo "[INFO] Starting Arch Linux installation..."

# Check root privileges
if (( EUID != 0 )); then
    echo "[ERROR] This script must be run as root!" >&2
    exit 1
fi

# Check UEFI mode
if [[ ! -d /sys/firmware/efi ]]; then
    echo "[ERROR] System not booted in UEFI mode." >&2
    exit 1
fi

UEFI_BITS=$(< /sys/firmware/efi/fw_platform_size 2>/dev/null || echo "unknown")
echo "[INFO] UEFI detected: ${UEFI_BITS}-bit"

# Device Selection
echo ""
echo "Available disks:"
lsblk -dno NAME,SIZE,MODEL

read -rp "Enter device to partition (e.g., sda or nvme0n1): " dev
[[ $dev == /dev/* ]] && DEVICE="$dev" || DEVICE="/dev/$dev"

if [[ ! -b $DEVICE ]]; then
    echo "[ERROR] Invalid device: $DEVICE" >&2
    exit 1
fi

echo ""
echo "Selected device: $DEVICE"
read -rp "This will ERASE ALL DATA on $DEVICE. Continue? (yes/no): " confirm

if [[ "${confirm,,}" != "yes" ]]; then
    echo "[INFO] Installation aborted by user."
    exit 0
fi

# Determine partition suffix (nvme/mmcblk need 'p', others don't)
BASE_NAME=$(basename "$DEVICE")
if [[ $BASE_NAME =~ ^(nvme|mmcblk) ]]; then
    PART_SUFFIX="p"
else
    PART_SUFFIX=""
fi

BOOT_PARTITION="${DEVICE}${PART_SUFFIX}1"
MAIN_PARTITION="${DEVICE}${PART_SUFFIX}2"

# Disk Partitioning
read -rp "Enter size for main partition (e.g., 50G, press Enter for all remaining): " mainsize

echo "[INFO] Wiping partition table..."
sgdisk -Z "$DEVICE"

echo "[INFO] Creating 1GiB EFI partition..."
sgdisk -n 1:0:+1G -t 1:ef00 -c 1:"$BOOT_LABEL" "$DEVICE"

if [[ -n "$mainsize" ]]; then
    echo "[INFO] Creating main partition ($mainsize)..."
    sgdisk -n 2:0:+${mainsize} -t 2:8300 -c 2:"$ROOT_LABEL" "$DEVICE"
else
    echo "[INFO] Creating main partition with remaining space..."
    sgdisk -n 2:0:0 -t 2:8300 -c 2:"$ROOT_LABEL" "$DEVICE"
fi

echo "[INFO] Partitions created: EFI -> $BOOT_PARTITION, ROOT -> $MAIN_PARTITION"

# LUKS2 Encryption Setup
echo "[INFO] Setting up LUKS2 encryption..."
[[ -b "/dev/mapper/$CRYPT_NAME" ]] && cryptsetup close "$CRYPT_NAME" 2>/dev/null || true

SECTOR_SIZE=$(lsblk -no PHY-SEC "$MAIN_PARTITION" 2>/dev/null || echo 512)
cryptsetup --type luks2 --verify-passphrase --sector-size "$SECTOR_SIZE" luksFormat "$MAIN_PARTITION"
cryptsetup open "$MAIN_PARTITION" "$CRYPT_NAME"
echo "[INFO] LUKS container opened at /dev/mapper/$CRYPT_NAME"

# Format Partitions
echo "[INFO] Formatting partitions..."
mkfs.fat -F32 "$BOOT_PARTITION"
mkfs.btrfs -f "/dev/mapper/$CRYPT_NAME"

# Btrfs Subvolumes
echo "[INFO] Creating Btrfs subvolumes..."
mount "/dev/mapper/$CRYPT_NAME" /mnt

# Create subvolumes
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@snapshots
btrfs subvolume create /mnt/@var_log
btrfs subvolume create /mnt/@var_cache
btrfs subvolume create /mnt/@swap

# Create standard directories
mkdir -p /mnt/{home,.snapshots,var/log,var/cache,swap}
chmod 700 /mnt/.snapshots

umount /mnt

# Mount Subvolumes
echo "[INFO] Mounting subvolumes..."

# Mount root
mount -o $BTRFS_OPTS,subvol=@ /dev/mapper/$CRYPT_NAME /mnt
mkdir -p /mnt/{home,.snapshots,var/log,var/cache,swap,efi}

# Mount other subvolumes
mount -o $BTRFS_OPTS,subvol=@home,nodev /dev/mapper/$CRYPT_NAME /mnt/home
mount -o $BTRFS_OPTS,subvol=@snapshots,nodev,nosuid,noexec /dev/mapper/$CRYPT_NAME /mnt/.snapshots
mount -o $BTRFS_OPTS,subvol=@var_log,nodev,nosuid,noexec /dev/mapper/$CRYPT_NAME /mnt/var/log
mount -o $BTRFS_OPTS,subvol=@var_cache,nodev,nosuid,noexec /dev/mapper/$CRYPT_NAME /mnt/var/cache
mount -o $BTRFS_OPTS,subvol=@swap,nodev,nosuid,noexec /dev/mapper/$CRYPT_NAME /mnt/swap

# Mount EFI
mount "$BOOT_PARTITION" /mnt/efi

# Create Btrfs Swap File
echo "[INFO] Creating Btrfs swap file..."
SWAPFILE="/mnt/swap/swapfile"
SWAP_SIZE_MB=8192

echo "[INFO] creating ${SWAP_SIZE_MB}MB swap file..."
btrfs filesystem mkswapfile --size "${SWAP_SIZE_MB}M" "$SWAPFILE"
chmod 600 "$SWAPFILE"
swapon "$SWAPFILE"

# CPU Microcode Selection
echo ""
echo "Select CPU microcode:"
echo "1) AMD    2) Intel    3) None"
read -rp "Choice [1-3]: " microcode_choice

case "$microcode_choice" in
    1) MICROCODE="amd-ucode" ;;
    2) MICROCODE="intel-ucode" ;;
    3) MICROCODE="" ;;
    *) echo "[ERROR] Invalid choice."; exit 1 ;;
esac

echo "[INFO] Selected microcode: ${MICROCODE:-None}"

# Install Base System
echo "[INFO] Installing base system..."
BASE_PACKAGES=(
    base base-devel
    linux-zen 
    linux-zen-headers
    linux-firmware
    btrfs-progs
    networkmanager
    terminus-font
    neovim
    sbctl
    openssh
    git
    zsh
)

[[ -n "$MICROCODE" ]] && BASE_PACKAGES+=("$MICROCODE")

pacstrap -K /mnt "${BASE_PACKAGES[@]}"

# Generate fstab
echo "[INFO] Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab
sed -i 's/subvolid=[0-9]*,//g' /mnt/etc/fstab

# System Configuration
echo "[INFO] Configuring system..."

# Hostname
read -rp "Hostname [$DEFAULT_HOSTNAME]: " input_hostname
HOSTNAME="${input_hostname:-$DEFAULT_HOSTNAME}"
echo "$HOSTNAME" > /mnt/etc/hostname

# Console
cat <<EOF > /mnt/etc/vconsole.conf
KEYMAP=us
FONT=ter-128b
EOF

# Locale
arch-chroot /mnt sed -i '/^#en_US.UTF-8 UTF-8/s/^#//' /etc/locale.gen
arch-chroot /mnt locale-gen
echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf

# Time
arch-chroot /mnt ln -sf /usr/share/zoneinfo/UTC /etc/localtime
arch-chroot /mnt hwclock --systohc

# User creation
read -rp "Username [$DEFAULT_USER]: " input_user
USERNAME="${input_user:-$DEFAULT_USER}"
arch-chroot /mnt useradd -G wheel -m "$USERNAME"

echo ""
echo "Set password for user '$USERNAME':"
arch-chroot /mnt passwd "$USERNAME"

echo ""
echo "Set password for root:"
arch-chroot /mnt passwd

# Hosts file
cat <<EOF > /mnt/etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain   ${HOSTNAME}
EOF

# Initramfs Configuration
echo "[INFO] Configuring initramfs..."

# Update mkinitcpio hooks
sed -i 's/^HOOKS=.*/HOOKS=(base systemd autodetect keyboard keymap sd-vconsole block sd-encrypt filesystems fsck)/' \
    /mnt/etc/mkinitcpio.conf

# Crypttab for initramfs
LUKS_UUID=$(blkid -s UUID -o value "$MAIN_PARTITION")
echo "${CRYPT_NAME} UUID=${LUKS_UUID} - password-echo=no,x-systemd.device-timeout=0,timeout=0,no-read-workqueue,no-write-workqueue,discard" \
    > /mnt/etc/crypttab.initramfs

# Kernel command line
CMDLINE_BASE="root=/dev/mapper/${CRYPT_NAME} rootfstype=btrfs rootflags=subvol=/@ rw"

echo "$CMDLINE_BASE mem_sleep_default=deep" > /mnt/etc/kernel/cmdline
echo "$CMDLINE_BASE" > /mnt/etc/kernel/cmdline_fallback

# Update mkinitcpio presets for UKI
for preset in /mnt/etc/mkinitcpio.d/*.preset; do
    sed -i "s/^[[:space:]]*PRESETS=('default')/# PRESETS=('default')/" "$preset"
    sed -i "s/^[[:space:]]*#*[[:space:]]*PRESETS=('default' 'fallback')/PRESETS=('default' 'fallback')/" "$preset"
    for key in default_uki fallback_uki default_image fallback_image default_options fallback_options; do
        sed -i "s/^[[:space:]]*#*[[:space:]]*\(${key}=\)/\1/" "$preset"
    done
done

# Generate initramfs
arch-chroot /mnt mkdir -p /efi/EFI/Linux
arch-chroot /mnt mkinitcpio -P

# Enable Services
echo "[INFO] Enabling system services..."
arch-chroot /mnt systemctl enable NetworkManager

# Bootloader Install
echo "Bootloader Install"
arch-chroot /mnt bootctl install

arch-chroot /mnt sbctl create-keys || true
chattr -i /sys/firmware/efi/efivars/* 2>/dev/null || true
arch-chroot /mnt sbctl enroll-keys --microsoft || true

arch-chroot /mnt sbctl sign -s /efi/EFI/BOOT/BOOTX64.EFI
arch-chroot /mnt sbctl sign -s /efi/EFI/Linux/arch-linux-zen-fallback.efi
arch-chroot /mnt sbctl sign -s /efi/EFI/Linux/arch-linux-zen.efi
arch-chroot /mnt sbctl sign -s /efi/EFI/systemd/systemd-bootx64.efi
arch-chroot /mnt sbctl verify

# edit sudoers file
arch-chroot /mnt EDITOR=nvim visudo

echo "Next steps:"
echo "1. Exit and unmount"
echo "2. Close LUKS: cryptsetup close $CRYPT_NAME"
echo "3. Reboot and enable Secure Boot in BIOS"
