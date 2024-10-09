#!/bin/bash

if ! command -v figlet &> /dev/null; then
    echo "Installing Figlet ..."
    sudo apt-get update && sudo apt-get install -y figlet
fi
sleep 1 
echo -e '\e[40m\e[92m'
figlet Empirex
echo -e '\e[0m'
sleep 1

# Check if required packages are installed, if not, install them
if ! dpkg -s wget lz4 aria2 pv >/dev/null 2>&1; then
    echo "Installing required packages..."
    sudo apt-get update
    sudo apt-get install wget lz4 aria2 pv -y
else
    echo "Required packages are already installed."
fi

# Stop the node services
echo "Stopping node services..."
sudo systemctl stop story
sudo systemctl stop story-geth

# Download Geth snapshot
echo "Downloading Geth snapshot..."
cd $HOME
aria2c -x 16 -s 16 http://story-snapshot.empirex.tech/Geth_snapshot.lz4

# Download Story snapshot
echo "Downloading Story snapshot..."
aria2c -x 16 -s 16 http://story-snapshot.empirex.tech/Story_snapshot.lz4

# Backup priv_validator_state.json
echo "Backing up priv_validator_state.json..."
mv $HOME/.story/story/data/priv_validator_state.json $HOME/.story/priv_validator_state.json.backup

# Remove old data
echo "Removing old data..."
rm -rf $HOME/.story/story/data
rm -rf $HOME/.story/geth/iliad/geth/chaindata

# Extract Story snapshot
echo "Extracting Story snapshot..."
sudo mkdir -p /root/.story/story/data
lz4 -d Story_snapshot.lz4 | pv | sudo tar xv -C /root/.story/story/

# Extract Geth snapshot
echo "Extracting Geth snapshot..."
sudo mkdir -p /root/.story/geth/iliad/geth/chaindata
lz4 -d Geth_snapshot.lz4 | pv | sudo tar xv -C /root/.story/geth/iliad/geth/

# Restore priv_validator_state.json
echo "Restoring priv_validator_state.json..."
mv $HOME/.story/priv_validator_state.json.backup $HOME/.story/story/data/priv_validator_state.json

# Restart node services
echo "Restarting node services..."
sudo systemctl start story
sudo systemctl start story-geth

# Remove snapshot files
echo "Removing snapshot files..."
sudo rm -rf Story_snapshot.lz4
sudo rm -rf Geth_snapshot.lz4
