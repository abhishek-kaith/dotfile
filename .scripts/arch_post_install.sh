#!/usr/bin/env bash
set -euo pipefail

# Helpers
install_pacman() {
  sudo pacman -Syu --needed --noconfirm "$@"
}

enable_service() {
  sudo systemctl enable --now "$1"
}

# Base system packages
BASE_PKGS=(
  base-devel sudo git
  man tldr tree less which
)

NETWORK_PKGS=(
  iputils bind-tools whois
  openssh wget curl
  networkmanager
)

SYSTEM_PKGS=(
  pciutils usbutils binutils lsof
  util-linux e2fsprogs dosfstools
  exfatprogs ntfs-3g
)

USER_ENV_PKGS=(
  zsh tmux
  xdg-user-dirs xdg-utils handlr
)

SECURITY_PKGS=(
  sbctl tpm2-tools tpm2-tss keepassxc fprintd
  pass pass-otp gnupg
)

ARCHIVE_PKGS=(
  p7zip libarchive unzip unrar
  tar gzip bzip2 xz zstd lz4
)

FONT_PKGS=(
  fontconfig
  ttf-dejavu
  noto-fonts noto-fonts-cjk noto-fonts-emoji
  ttf-jetbrains-mono ttf-jetbrains-mono-nerd
  ttf-font-awesome ttf-nerd-fonts-symbols
)

echo "[*] Installing base system packages..."
install_pacman \
  "${BASE_PKGS[@]}" \
  "${NETWORK_PKGS[@]}" \
  "${SYSTEM_PKGS[@]}" \
  "${USER_ENV_PKGS[@]}" \
  "${SECURITY_PKGS[@]}" \
  "${ARCHIVE_PKGS[@]}" \
  "${FONT_PKGS[@]}"

enable_service NetworkManager

# User directories & fonts
xdg-user-dirs-update
fc-cache -fv

# Mise
MISE_BIN="$HOME/.local/bin/mise"

if [[ ! -x "$MISE_BIN" ]]; then
  echo "[*] Installing mise..."
  mkdir -p "$HOME/.local/bin"
  curl -fsSL https://mise.jdx.dev/install.sh | sh -s -- --no-modify-path --no-activate
else
  echo "[*] Mise already installed."
fi

# Dotfiles (bare repo)
DOTFILE_REPO="$HOME/.cfg"
GIT_REPO="https://github.com/abhishek-kaith/dotfile"

if [[ ! -d "$DOTFILE_REPO" ]]; then
  echo "[*] Cloning dotfiles..."
  git clone --bare "$GIT_REPO" "$DOTFILE_REPO"
  git --git-dir="$DOTFILE_REPO" --work-tree="$HOME" checkout
  git --git-dir="$DOTFILE_REPO" --work-tree="$HOME" config --local status.showUntrackedFiles no
else
  echo "[*] Dotfiles already present."
fi

# Mise tools
MISE_CONFIG="$HOME/.config/mise/config.toml"
if [[ -f "$MISE_CONFIG" ]]; then
  "$MISE_BIN" install
fi

# Audio (PipeWire + RNNoise)
AUDIO_PKGS=(
  pipewire pipewire-alsa pipewire-jack pipewire-pulse
  wireplumber rtkit pavucontrol alsa-utils
  gst-plugin-pipewire
)

install_pacman "${AUDIO_PKGS[@]}"

systemctl --user enable --now pipewire pipewire-pulse wireplumber
sudo usermod -aG rtkit "$USER"

if [[ ! -f /usr/local/lib/ladspa/librnnoise_ladspa.so ]]; then
  echo "[*] Installing RNNoise..."
  wget -q https://github.com/werman/noise-suppression-for-voice/releases/download/v1.10/linux-rnnoise.zip
  unzip -q linux-rnnoise.zip
  sudo install -Dm644 \
    linux-rnnoise/ladspa/librnnoise_ladspa.so \
    /usr/local/lib/ladspa/librnnoise_ladspa.so
  rm -rf linux-rnnoise linux-rnnoise.zip
fi

# yay (AUR helper)
if ! command -v yay &>/dev/null; then
  echo "[*] Installing yay..."
  git clone https://aur.archlinux.org/yay.git
  (cd yay && makepkg -si --noconfirm)
  rm -rf yay
fi

# Power management & monitoring
yay -S --needed --noconfirm \
  power-profiles-daemon tlp ryzenadj \
  powertop btop

enable_service power-profiles-daemon

# Firewall UFW
install_pacman ufw

sudo ufw reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw logging on
sudo ufw --force enable
sudo ufw status verbose

# Wayland / Desktop
DESKTOP_PKGS=(
  niri alacritty fuzzel
  xwayland-satellite
  polkit-gnome
  xdg-desktop-portal
  xdg-desktop-portal-gtk
  xdg-desktop-portal-gnome
)

install_pacman "${DESKTOP_PKGS[@]}"

yay -S --needed --noconfirm \
  dms-shell-bin dsearch-bin cliphist cava khal matugen \
  qt5-multimedia accountsservice

systemctl --user add-wants niri.service dms
systemctl --user enable --now dsearch

# Apps & accessibility
install_pacman \
  qt5-wayland \
  speech-dispatcher libnotify \
  hunspell-en_US festival espeak-ng

yay -S --needed --noconfirm zen-browser-bin

# File manager & media
install_pacman \
  nautilus udiskie evince mpv ffmpeg imagemagick \
  gvfs gvfs-{afc,gphoto2,mtp,nfs,smb,google,wsdd} \
  ffmpegthumbnailer poppler gdk-pixbuf2 \
  librsvg libgepub libopenraw tumbler gthumb

# Theming
install_pacman \
  adwaita-icon-theme papirus-icon-theme \
  flatpak adw-gtk-theme nwg-look qt6ct

gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3'
flatpak install -y org.gtk.Gtk3theme.adw-gtk3{,-dark}

echo "[*] Setup complete!"
