#!/usr/bin/env bash

sudo tailscale up --authkey $TAILSCALE_KEY --hostname kumu

if [[ $(tailscale status) == *kumu* ]] ; then
  sudo ufw delete allow 22/tcp
  sudo ufw reload
  sudo service ssh restart
  exit
fi
