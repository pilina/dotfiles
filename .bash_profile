# do a decrypt so all the files are present
if [ ! -f "$HOME/.bashenv" ] ; then
  yadm decrypt
fi

# if running bash
if [ -n "$BASH_VERSION" ] ; then
  # include .bashrc if it exists
  if [ -f "$HOME/.bashrc" ] ; then
    . "$HOME/.bashrc"
  fi
fi

# set PATH so it includes user's private bin if it exists
if [ -d "$HOME/.bin" ] ; then
  PATH="$HOME/.bin:$PATH"
fi

# set PATH so it includes user's private bin if it exists
if [ -d "$HOME/.local/bin" ] ; then
  PATH="$HOME/.local/bin:$PATH"
fi

# pull dotfile changes
if [[ $(yadm pull) == *yadm/archive* ]] ; then
  yadm decrypt
fi

echo "Bash Env exits: $(-f $HOME/.bashenv)"
# source .bashenv
if [ -f "$HOME/.bashenv" ] ; then
  . "$HOME/.bashenv"
fi

# log in to tailscale
if [[ $(tailscale status) == *stopped* ]] ; then
  sudo tailscale up --authkey $TAILSCALE_KEY
fi
