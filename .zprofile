if [ -z "$SSH_AUTH_SOCK" ]; then
  eval "$(ssh-agent -s)"
fi

#if [[ -z "$DISPLAY" ]] && [[ $(tty) = /dev/tty1 ]]; then
#  niri-session
#fi
