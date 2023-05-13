#!/bin/bash

echo "install requirement pacakges"
apt update && apt install -y \
  tmux

cp -fa tmux.conf ~/.tmux.conf
