#!/bin/bash

echo "install requirement pacakges"
apt update && apt install -y \
  curl \
  zsh \
  git

echo "install oh my zsh refer (https://github.com/ohmyzsh/ohmyzsh/wiki)"
sh -c "RUNZSH=no $(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

echo "install theme for oh my zsh"
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k

echo -e "In zsh environment. Run these command to setup theme"
echo -e "\tomz theme set powerlevel10k/powerlevel10k"
