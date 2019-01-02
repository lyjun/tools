#!/bin/bash

echo "install packages"
sudo apt-get install -y vim git python-dev cmake clang

[ -d ~/.vim/bundle/Vundle.vim ] || (echo "git clone VundleVim" && git clone https://github.com/VundleVim/Vundle.vim.git ~/.vim/bundle/Vundle.vim)

echo "copy vimrc file"
cp vimrc ~/.vimrc

echo "Plugin install"
vim -c "PluginInstall" -c "qa"

[ -d ~/.vim/bundle/YouCompleteMe ] && (echo "Build YouCompleteMe" && cd ~/.vim/bundle/YouCompleteMe && ./install.py --clang-completer)