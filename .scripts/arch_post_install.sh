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

  # Filesystems
  util-linux
  e2fsprogs
  dosfstools
  exfatprogs
  ntfs-3g

  # User environment
  xdg-user-dirs
  tmux
  zsh

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
sudo pacman -S p7zip libarchive unzip unrar tar gzip bzip2 xz zstd lz4 --needed --noconfirm

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

sudo pacman -S pipewire pipewire-alsa pipewire-jack pipewire-pulse gst-plugin-pipewire wireplumber rtkit pavucontrol alsa-utils  --needed --noconfirm
wget https://github.com/werman/noise-suppression-for-voice/releases/download/v1.10/linux-rnnoise.zip
unzip linux-rnnoise.zip
sudo mkdir -p /usr/local/lib/ladspa
sudo cp linux-rnnoise/ladspa/librnnoise_ladspa.so /usr/local/lib/ladspa/
sudo rm -rf linux-rnnoise.zip
sudo rm -rf linux-rnnoise
sudo chmod 644 /usr/local/lib/ladspa/librnnoise_ladspa.so
sudo usermod -a -G rtkit $USER
systemctl --user enable pipewire pipewire-pulse wireplumber

git clone https://aur.archlinux.org/yay yay
cd yay
makepkg -si
cd ..
sudo rm -rf yay

yay -S --needed --noconfirm power-profiles-daemon tlp ryzenadj btop powertop
sudo systemctl enable --now power-profiles-daemon

sudo pacman -S ufw --needed --noconfirm
sudo ufw reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
# sudo ufw allow ssh
# sudo ufw limit ssh
# Allow local network access (optional, adjust subnet if needed)
# sudo ufw allow from 192.168.0.0/24
# Allow basic web traffic if needed
# sudo ufw allow 80/tcp   # HTTP
# sudo ufw allow 443/tcp  # HTTPS
# Enable logging for debugging
sudo ufw logging on
# Enable UFW
sudo ufw --force enable
# Show status
sudo ufw status verbose

sudo pacman -Sy niri alacritty fuzzel xwayland-satellite xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-gnome  --needed --noconfirm

yay -S noctalia-shell cliphist matugen cava wlsunset power-profiles-daemon --needed --noconfirm
systemctl --user enable --now noctalia.service

sudo pacman -S speech-dispatcher libnotify hunspell-en_US festival espeak-ng --needed --noconfirm

sudo pacman -Syu nautilus evince mpv ffmpeg imagemagick gvfs gvfs-afc gvfs-gphoto2 gvfs-mtp gvfs-nfs gvfs-smb gvfs-google gvfs-wsdd ffmpegthumbnailer poppler gdk-pixbuf2 librsvg libgepub libopenraw tumbler gthumb --needed --noconfirm

sudo pacman -S flatpak adw-gtk-theme nwg-look qt6ct
flatpak install flathub app.zen_browser.zen
flatpak install org.gtk.Gtk3theme.adw-gtk3-dark
flatpak install org.gtk.Gtk3theme.adw-gtk3

# firefox onnxruntime 

echo "[*] Setup complete!"
