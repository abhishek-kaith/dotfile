#!/usr/bin/env bash

if [[ $# -eq 1 ]]; then
    selected=$1
else
    selected=$(find ~/ ~/Projects ~/Projects/work ~/Projects/personal -mindepth 1 -maxdepth 1 -type d | fzf)
fi

if [[ -z $selected ]]; then
    exit 0
fi

session_name=$(basename "$selected" | tr . _)

if [[ -n $TMUX ]]; then
    if ! tmux has-session -t="$session_name" 2> /dev/null; then
        tmux new-session -ds "$session_name" -c "$selected"
    fi
    tmux switch-client -t "$session_name"
else
    if ! tmux has-session -t="$session_name" 2> /dev/null; then
        tmux new-session -s "$session_name" -c "$selected"
    else
        tmux attach-session -t "$session_name"
    fi
fi
