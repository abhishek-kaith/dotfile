#!/usr/bin/env bash
set -euo pipefail

sudo pacman -S --needed --noconfirm \
  \
  #Base & build
  base-devel \
  sudo \
  git \
  \
  #Help & usability
  man \
  tldr \
  tree \
  less \
  which \
  \
  #Networking
  iputils \
  dnsutils \
  whois \
  openssh \
  wget \
  curl \
  networkmanager \
  \
  #Hardware & system
  pciutils \
  usbutils \
  binutils \
  lsof \
  btop \
  \
  #Filesystems 
  util-linux \
  e2fsprogs \
  dosfstools \
  exfatprogs \
  ntfs-3g \
  \
  #User environment
  xdg-user-dirs \
  tmux \
  \
  #Secure Boot & TPM
  sbctl \
  tpm2-tools \
  tpm2-tss \
  \
  #Password management
  pass \
  pass-otp \
  gnupg \
  \
  #Fonts (for future GUI / terminal readiness)
  ttf-dejavu \
  noto-fonts \
  noto-fonts-cjk \
  noto-fonts-emoji \
  ttf-jetbrains-mono \
  ttf-jetbrains-mono-nerd \
  ttf-font-awesome \
  ttf-nerd-fonts-symbols \
  ttf-symbola

sudo systemctl enable --now NetworkManager
xdg-user-dirs-update
fc-cache -fv

alias config='/usr/bin/git --git-dir=$HOME/.cfg/ --work-tree=$HOME'
echo "alias config='/usr/bin/git --git-dir=$HOME/.cfg/ --work-tree=$HOME'" >> $HOME/.bashrc
git clone --bare https://github.com/abhishek-kaith/dotfile $HOME/.cfg
echo  "NOTE add .cfg in gitignore"
echo  "config config --local status.showUntrackedFiles no"
