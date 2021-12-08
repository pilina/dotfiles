#!/usr/bin/env bash

# Everything needs to be run as root
if [ $(id -u) -ne 0 ]; then
  printf "Script must be run as root.\n"
  exit 1
fi

read -p "Enter the username [pi]: " USERNAME
USERNAME=${USERNAME:-pi}
read -p "Enter the yadm repo [https://github.com/pilina/dotfiles.git]: " YADM_REPO
YADM_REPO=${YADM_REPO:-"https://github.com/pilina/dotfiles.git"}
read -p "Enter the tailscale key: " TAILSCALE_KEY

main() {
  dependencies
  disable_wifi
  setup_ssh
  install_ufw
  install_tailscale
  setup_btrfs
  setup_docker
}

dependencies() {
  # first let's update the system
  apt update && apt -y upgrade
  # install dependencies
  apt -y install ca-certificates git curl gnupg sudo ufw vim fuse lsb-release
}

install_yadm() {
  # install yadm
  curl -fLo /usr/local/bin/yadm https://github.com/TheLocehiliosan/yadm/raw/master/yadm
  # apply executable permission
  chmod a+x /usr/local/bin/yadm
  # clone
  su -c "yadm clone --bootstrap ${YADM_REPO}" $USERNAME
}

disable_wifi() {
  # disable wifi and bluetooth
  systemctl disable wpa_supplicant
  systemctl disable bluetooth
  systemctl disable hciuart
}

setup_ssh() {
  # No Root Login
  sed -i "s/.*PermitRootLogin.*/PermitRootLogin no/g" /etc/ssh/sshd_config
  # No Password Auth
  sed -i "s/.*PasswordAuthentication.*/PasswordAuthentication no/g" /etc/ssh/sshd_config
  # Change Address Family
  sed -i "s/.*AddressFamily.*/AddressFamily inet/g" /etc/ssh/sshd_config
  # restart ssh to apply new config
  service ssh restart
}

install_ufw() {
  echo "Installing UFW"
  apt update && apt -y upgrade
  apt -y install ufw

  echo "Setting sane defaults"
  # firewall default deny incoming
  ufw default deny incoming
  # firewall default allow outgoing
  ufw default allow outgoing
  # firewall allow ssh
  ufw allow ssh/tcp
  # enable firewall
  ufw enable
}

install_tailscale() {
  apt update && apt -y upgrade
  apt -y install lsb-release

  # Add Tailscale's GPG key
  curl -fsSL https://pkgs.tailscale.com/stable/debian/$(lsb_release -cs).gpg | gpg --dearmor -o /usr/share/keyrings/tailscale-archive-keyring.gpg
  # Add the tailscale repository
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/debian \
    $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/tailscale.list > /dev/null
  # Install Tailscale
  apt update && apt -y install tailscale
  # lock it down
  ufw allow in on tailscale0
  ufw allow 41641/udp

  if [ -z "$TAILSCALE_KEY" ]; then
    tailscale up --authkey $TAILSCALE_KEY

    ufw delete allow 22/tcp
    ufw reload
    service ssh restart
  fi
}

_create_partition() {
  parted /dev/sda --script mklabel gpt
  parted -a optimal /dev/sda --script mkpart primary btrfs 0% 100%
  mkfs.btrfs -L data /dev/sda1
}

setup_btrfs() {
  echo "Setting up BTRFS"
  apt update && apt -y upgrade
  apt -y install btrfs-progs zstd

  echo "Create a new disk partition"
  while true; do
      read -p "Do you want to partition your harddrive?" yn
      case $yn in
          [Yy]* ) _create_partition; break;;
          [Nn]* ) break;;
          * ) echo "Please answer yes or no.";;
      esac
  done

  echo "Create mount point"
  mkdir -p /var/lib/docker

  echo "Adding to fstab"
  partuuid=$(ls -l /dev/disk/by-partuuid/ | grep sda1 | awk -F" " '{print $9}')
  echo \
    "PARTUUID=$partuuid /var/lib/docker btrfs defaults,noatime,compress=zstd 0 2" \
    | tee -a /etc/fstab > /dev/null

  echo "Mount everything"
  mount -a
}

setup_docker() {
  apt update && apt -y upgrade
  apt -y install lsb-release gpg

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
  docker swarm init --advertise-addr $(tailscale ip -4)
  # set up an egress network
  docker network create --driver=overlay public

  echo "Updating /etc/ufw/after.rules"
  cat <<EOF | sudo tee -a /etc/ufw/after.rules > /dev/null

# https://github.com/chaifeng/ufw-docker#solving-ufw-and-docker-issues
# BEGIN UFW AND DOCKER
*filter
:ufw-user-forward - [0:0]
:ufw-docker-logging-deny - [0:0]
:DOCKER-USER - [0:0]
-A DOCKER-USER -j ufw-user-forward

-A DOCKER-USER -j RETURN -s 10.0.0.0/8
-A DOCKER-USER -j RETURN -s 172.16.0.0/12
-A DOCKER-USER -j RETURN -s 192.168.0.0/16

-A DOCKER-USER -p udp -m udp --sport 53 --dport 1024:65535 -j RETURN

-A DOCKER-USER -j ufw-docker-logging-deny -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -d 192.168.0.0/16
-A DOCKER-USER -j ufw-docker-logging-deny -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -d 10.0.0.0/8
-A DOCKER-USER -j ufw-docker-logging-deny -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -d 172.16.0.0/12
-A DOCKER-USER -j ufw-docker-logging-deny -p udp -m udp --dport 0:32767 -d 192.168.0.0/16
-A DOCKER-USER -j ufw-docker-logging-deny -p udp -m udp --dport 0:32767 -d 10.0.0.0/8
-A DOCKER-USER -j ufw-docker-logging-deny -p udp -m udp --dport 0:32767 -d 172.16.0.0/12

-A DOCKER-USER -j RETURN

-A ufw-docker-logging-deny -m limit --limit 3/min --limit-burst 10 -j LOG --log-prefix "[UFW DOCKER BLOCK] "
-A ufw-docker-logging-deny -j DROP

COMMIT
# END UFW AND DOCKER
EOF

  echo "Reloading UFW"
  ufw reload
}

main
exit 0
