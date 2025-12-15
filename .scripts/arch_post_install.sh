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
  bind-tools
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

  # Fonts
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

echo "[*] Installing Mise (non-intrusive)..."

MISE_BIN="$HOME/.local/bin/mise"

if [ ! -x "$MISE_BIN" ]; then
  mkdir -p "$HOME/.local/bin"
  curl -fsSL https://mise.jdx.dev/install.sh | sh -s -- --no-modify-path --no-activate
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

git --git-dir="$DOTFILE_REPO" --work-tree="$HOME" checkout
git --git-dir="$DOTFILE_REPO" --work-tree="$HOME" config --local status.showUntrackedFiles no


MISE_CONFIG="$HOME/.config/mise/config.toml"

if [ -f "$MISE_CONFIG" ]; then
  echo "[*] Installing tools from $MISE_CONFIG (manual mode)..."
  "$MISE_BIN" install
else
  echo "[*] No mise config found at $MISE_CONFIG"
fi

sudo pacman -S  pipewire pipewire-audio pipewire-alsa pipewire-pulse pipewire-jack wireplumber pavucontrol
git clone https://github.com/werman/noise-suppression-for-voice.git
cd noise-suppression-for-voice
make
sudo mkdir -p /usr/local/lib/ladspa
sudo cp librnnoise_ladspa.so /usr/local/lib/ladspa/
cd ..
rm -rf noise-suppression-for-voice

echo "[*] Setup complete!"
echo "NOTE:"
echo "- mise is installed but NOT hooked into any shell"
echo "- use ~/.local/bin/mise exec ... explicitly"
echo "- no shell restart required"
