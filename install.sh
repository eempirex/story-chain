#!/bin/bash

# Function to check if a command exists
exists() {
  command -v "$1" >/dev/null 2>&1
}

# Function to install a package if it's missing
install_if_missing() {
  if ! exists "$1"; then
    echo -e "\e[33mInstalling $1...\e[0m"
    sudo apt update && sudo apt install -y "$1" < "/dev/null"
  fi
}

# Install curl and figlet if missing
install_if_missing curl
install_if_missing figlet

# Source bash_profile if it exists
[ -f "$HOME/.bash_profile" ] && source "$HOME/.bash_profile"

# Display banner using figlet
echo -e '\e[40m\e[92m'
figlet Empirex
echo -e '\e[0m'

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
RESET='\033[0m'

# Get and check the Ubuntu version (must be 22.04 or higher)
version=$(lsb_release -r | awk '{print $2}' | sed 's/\.//')
min_version=2204
if [ "$version" -lt "$min_version" ]; then
  echo -e "${RED}Current Ubuntu Version: $(lsb_release -r | awk '{print $2}').${RESET}"
  echo -e "${RED}Required Ubuntu Version: 22.04 or higher.${RESET}"
  exit 1
fi

# DAEMON and service setup
NODE="story"
DAEMON_HOME="$HOME/.story/story"
DAEMON_NAME="story"
if [ -d "$DAEMON_HOME" ]; then
    new_folder_name="${DAEMON_HOME}_$(date +"%Y%m%d_%H%M%S")"
    mv "$DAEMON_HOME" "$new_folder_name"
fi

# Prompt for validator name
if [ -z "$VALIDATOR" ]; then
    read -p "Enter validator name: " VALIDATOR
    echo "export VALIDATOR='${VALIDATOR}'" >> $HOME/.bash_profile
fi

echo 'source $HOME/.bashrc' >> $HOME/.bash_profile
source $HOME/.bash_profile
sleep 1

# Install necessary packages
cd $HOME
echo -e "\n\e[42mInstalling dependencies...\e[0m" && sleep 1
sudo apt update
sudo apt install make unzip clang pkg-config lz4 libssl-dev build-essential git jq ncdu bsdmainutils htop -y < "/dev/null"

# Install Go
echo -e '\n\e[42mInstalling Go...\e[0m\n' && sleep 1
VERSION=1.23.0
wget -O go.tar.gz https://go.dev/dl/go$VERSION.linux-amd64.tar.gz
sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go.tar.gz && rm go.tar.gz
echo 'export GOROOT=/usr/local/go' >> $HOME/.bash_profile
echo 'export GOPATH=$HOME/go' >> $HOME/.bash_profile
echo 'export GO111MODULE=on' >> $HOME/.bash_profile
echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> $HOME/.bash_profile && . $HOME/.bash_profile
go version

# Install software
echo -e '\n\e[42mInstalling Story software...\e[0m\n' && sleep 1

cd $HOME
rm -rf story

wget -O story-linux-amd64-0.10.1-57567e5.tar.gz https://story-geth-binaries.s3.us-west-1.amazonaws.com/story-public/story-linux-amd64-0.10.1-57567e5.tar.gz
tar xvf story-linux-amd64-0.10.1-57567e5.tar.gz
sudo chmod +x story-linux-amd64-0.10.1-57567e5/story
sudo mv story-linux-amd64-0.10.1-57567e5/story /usr/local/bin/
story version

cd $HOME
rm -rf story-geth

wget -O geth-linux-amd64-0.9.3-b224fdf.tar.gz https://story-geth-binaries.s3.us-west-1.amazonaws.com/geth-public/geth-linux-amd64-0.9.3-b224fdf.tar.gz
tar xvf geth-linux-amd64-0.9.3-b224fdf.tar.gz
sudo chmod +x geth-linux-amd64-0.9.3-b224fdf/geth
sudo mv geth-linux-amd64-0.9.3-b224fdf/geth /usr/local/bin/story-geth

# Initialize daemon
$DAEMON_NAME init --network iliad --moniker "${VALIDATOR}"
sleep 1
$DAEMON_NAME validator export --export-evm-key --evm-key-path $HOME/.story/.env
$DAEMON_NAME validator export --export-evm-key >>$HOME/.story/story/config/wallet.txt
cat $HOME/.story/.env >>$HOME/.story/story/config/wallet.txt

# Create systemd service for story-geth
sudo tee /etc/systemd/system/story-geth.service > /dev/null <<EOF  
[Unit]
Description=Story execution daemon
After=network-online.target

[Service]
User=$USER
ExecStart=/usr/local/bin/story-geth --iliad --syncmode full
Restart=always
RestartSec=3
LimitNOFILE=infinity
LimitNPROC=infinity

[Install]
WantedBy=multi-user.target
EOF

# Create systemd service for story
sudo tee /etc/systemd/system/$NODE.service > /dev/null <<EOF  
[Unit]
Description=Story consensus daemon
After=network-online.target

[Service]
User=$USER
WorkingDirectory=$HOME/.story/story
ExecStart=/usr/local/bin/story run
Restart=always
RestartSec=3
LimitNOFILE=infinity
LimitNPROC=infinity

[Install]
WantedBy=multi-user.target
EOF

# Enable persistent logging
sudo tee <<EOF >/dev/null /etc/systemd/journald.conf
Storage=persistent
EOF

# Check for port conflicts and update config files
PORT=335
for port in 26656 26657 26658 1317; do
  if ss -tulpen | awk '{print $5}' | grep -q ":${port}$"; then
    echo -e "${RED}Port ${port} already in use.${RESET}"
    sed -i -e "s|:${port}\"|:${PORT}${port: -2}\"|" $DAEMON_HOME/config/config.toml
    echo -e "${YELLOW}Port ${port} changed to ${PORT}${port: -2}.${RESET}"
    sleep 2
  fi
done

# Restart services
sudo systemctl restart systemd-journald
sudo systemctl daemon-reload
sudo systemctl enable $NODE
sudo systemctl restart $NODE
sudo systemctl enable story-geth
sudo systemctl restart story-geth
sleep 5

# Check node status
echo -e '\n\e[42mChecking node status...\e[0m\n' && sleep 1
if [[ $(service $NODE status | grep active) =~ "running" ]]; then
  echo -e "Your $NODE node \e[32minstalled and is running!\e[0m"
  echo -e "You can check the logs with \e[32mjournalctl -fu $NODE\e[0m"
else
  echo -e "Your $NODE node \e[31mfailed to start.\e[0m"
  echo -e "You can check the logs with \e[32mjournalctl -fu $NODE\e[0m"
fi
