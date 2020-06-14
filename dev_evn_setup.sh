#!/bin/bash -e

# define color
RED='\033[0;31m'
NC='\033[0m'


install_apt_package () {
	echo "install $@"
	sudo apt-get install -y $@
}


install_essential_package () {
	install_apt_package wget git
}


# install zsh 
config_zsh() {
	# zsh
	install_apt_package zsh
	# oh my zsh
	env RUNZSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
	# "bullet-train" theme for zsh
	wget http://raw.github.com/caiogondim/bullet-train-oh-my-zsh-theme/master/bullet-train.zsh-theme -O /tmp/bullet-train.zsh-theme
	mv /tmp/bullet-train.zsh-theme ${HOME}/.oh-my-zsh/themes/bullet-train.zsh-theme
	sed -i 's/^ZSH_THEME="[a-zA-Z-]*"$/ZSH_THEME="bullet-train"/g' ${HOME}/.zshrc
	# reload tip
	echo -e "${RED}[INFO]${NC} Don't forget to run 'source ${HOME}/.zshrc'"
}


# basic pacakge
install_essential_package
# zsh with oh my zsh
config_zsh
