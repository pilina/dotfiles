#!/usr/bin/env bash

# Everything needs to be run as root
if [ $(id -u) -ne 0 ]; then
  printf "Script must be run as root.\n"
  exit 1
fi

DEBIAN_FRONTEND=noninteractive
USERNAME=pilina
YADM_REPO=https://github.com/pilina/dotfiles.git

main() {
  dependencies
  create_user
  if [ ! -f /.dockerenv ] ; then
    setup_ssh_firewall
    setup_tailscale
    setup_docker
    reboot
  fi
}

dependencies() {
  # prepare the system
  apt update && apt -y upgrade
  # install dependencies
  apt -y install ca-certificates \
      git \
      curl \
      gnupg \
      sudo \
      ufw \
      vim \
      lsb-release
}

setup_ssh_firewall() {
  # No Root Login
  sed -i "s/.*PermitRootLogin.*/PermitRootLogin no/g" /etc/ssh/sshd_config
  # No Password Auth
  sed -i "s/.*PasswordAuthentication.*/PasswordAuthentication no/g" /etc/ssh/sshd_config
  # Change Address Family
  sed -i "s/.*AddressFamily.*/AddressFamily inet/g" /etc/ssh/sshd_config

  # firewall default deny incoming
  ufw default deny incoming
  # firewall default allow outgoing
  ufw default allow outgoing
  # firewall allow ssh
  ufw allow ssh/tcp
  # enable firewall
  ufw enable
}

setup_docker() {
  [ -f /.dockerenv ] && return
  # add docker gpg key
  curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  # add docker repository
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian \
    $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
  # install docker engine
  apt update && apt -y install docker-ce docker-ce-cli containerd.io
  # enable docker and containerd service
  systemctl enable docker.service
  systemctl enable containerd.service
  # add user to docker group if we're not in a docker env
  adduser $USERNAME docker
  # init docker swarm
  docker swarm init
  # set up an egress network
  docker network create --driver=overlay public
}

create_user() {
  # create a shell user
  adduser --shell /bin/bash --uid 1000 --gecos "" --disabled-password $USERNAME
  # add pilina to sudoers
  adduser $USERNAME sudo
  # no password necessary for sudo
  echo "${USERNAME}      ALL=(ALL)       NOPASSWD: ALL" >> /etc/sudoers.d/$USERNAME
  # create the ssh folder for the user
  su -c "mkdir ~/.ssh" $USERNAME
  # create the pubkey for the user
  if [ ! -f /.dockerenv ] ; then
    AUTHORIZED_COMMAND="echo '$(cat ~/.ssh/authorized_keys)' >> ~/.ssh/authorized_keys"
    su -c "$AUTHORIZED_COMMAND" $USERNAME
    # change access to file
    chmod 600 /home/$USERNAME/.ssh/authorized_keys
    # restart sshd
    systemctl restart sshd
  fi
  # add github to known hosts
  su -c "touch /home/${USERNAME}/.ssh/known_hosts" $USERNAME
  su -c "ssh-keyscan -H github.com >> ~/.ssh/known_hosts" $USERNAME
  su -c "chmod 600 ~/.ssh/known_hosts" $USERNAME
  # install yadm
  curl -fLo /usr/local/bin/yadm https://github.com/TheLocehiliosan/yadm/raw/master/yadm
  # apply executable permission
  chmod a+x /usr/local/bin/yadm
  # clone yadm repo
  sudo --background -u $USERNAME -- yadm clone --bootstrap ${YADM_REPO}
}

setup_tailscale() {
  # Add Tailscale's GPG key
  curl -fsSL https://pkgs.tailscale.com/stable/debian/$(lsb_release -cs).gpg | gpg --dearmor -o /usr/share/keyrings/tailscale-archive-keyring.gpg
  # Add the tailscale repository
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/debian \
    $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/tailscale.list > /dev/null
  # Install Tailscale
  apt update && apt -y install tailscale
  # Enable IP Forwarding to make this an exit server
  echo 'net.ipv4.ip_forward = 1' | tee -a /etc/sysctl.conf
  echo 'net.ipv6.conf.all.forwarding = 1' | tee -a /etc/sysctl.conf
  sysctl -p /etc/sysctl.conf
  # lock it down
  ufw allow in on tailscale0
  ufw allow 41641/udp
}

main
