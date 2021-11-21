#!/usr/bin/env bash

# Everything needs to be run as root
if [ $(id -u) -ne 0 ]; then
  printf "Script must be run as root.\n"
  exit 1
fi

DEBIAN_FRONTEND=noninteractive

# prepare the system
apt update && apt -y upgrade
# install dependencies
apt -y install ca-certificates \
    git \
    curl \
    gnupg \
    sudo \
    lsb-release

# create a shell user
adduser --shell /bin/bash --uid 1000 --gecos "" --disabled-password pilina

if [ ! -f /.dockerenv ]; then
  # add docker gpg key
  curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  # add docker repository
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian \
    $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  # install docker engine
  apt update && apt -y install docker-ce docker-ce-cli containerd.io
  # init docker swarm
  docker swarm init
  # set up an egress network
  docker network create --driver=overlay public
  # add to docker group
  adduser pilina docker
fi

# install yadm
curl -fLo /usr/local/bin/yadm https://github.com/TheLocehiliosan/yadm/raw/master/yadm
# apply executable permission
chmod a+x /usr/local/bin/yadm

# clone yadm repo
su -c "yadm --bootstrap clone https://github.com/pilina/dotfiles.git" - pilina

# reset password
passwd -de pilina
# add pilina to sudoers
adduser pilina sudo
