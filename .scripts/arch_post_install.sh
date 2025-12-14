#!/usr/bin/env bash
set -euo pipefail
PKGS=(
  # Base & build
  base-devel
  sudo
  git

  # Help & usability
  man
  tldr
  tree
  less
  which

  # Networking
  iputils
  bind-tools          # 'dnsutils' equivalent in Arch
  whois
  openssh
  wget
  curl
  networkmanager

  # Hardware & system
  pciutils
  usbutils
  binutils
  lsof
  btop

  # Filesystems
  util-linux
  e2fsprogs
  dosfstools
  exfatprogs
  ntfs-3g

  # User environment
  xdg-user-dirs
  tmux

  # Secure Boot & TPM
  sbctl
  tpm2-tools
  tpm2-tss

  # Password management
  pass
  pass-otp
  gnupg

  # Fonts (future GUI / terminal readiness)
  ttf-dejavu
  noto-fonts
  noto-fonts-cjk
  noto-fonts-emoji
  ttf-jetbrains-mono
  ttf-jetbrains-mono-nerd
  ttf-font-awesome
  ttf-nerd-fonts-symbols
  fontconfig
)

echo "[*] Installing packages..."
sudo pacman -Syu --needed --noconfirm "${PKGS[@]}"

echo "[*] Enabling NetworkManager..."
sudo systemctl enable --now NetworkManager

echo "[*] Updating user directories..."
xdg-user-dirs-update

echo "[*] Refreshing font cache..."
fc-cache -fv

echo "[*] Installing Mise..."
if ! command -v mise &> /dev/null; then
  curl -fsSL https://mise.run/zsh | sh
else
  echo "[*] Mise already installed."
fi

DOTFILE_REPO="$HOME/.cfg"
GIT_REPO="https://github.com/abhishek-kaith/dotfile"

if [ ! -d "$DOTFILE_REPO" ]; then
  echo "[*] Cloning dotfiles..."
  git clone --bare "$GIT_REPO" "$DOTFILE_REPO"
else
  echo "[*] Dotfiles repository already exists."
fi

# Git alias for managing dotfiles
if ! grep -q "alias config=" "$HOME/.bashrc"; then
  echo "alias config='/usr/bin/git --git-dir=$HOME/.cfg/ --work-tree=$HOME'" >> "$HOME/.bashrc"
  echo "config config --local status.showUntrackedFiles no" >> "$HOME/.bashrc"
fi

echo "[*] Setup complete!"
echo "NOTE: Add .cfg in .gitignore if not already done."
echo "Run 'source ~/.bashrc' or restart your shell to load 'config' alias."

