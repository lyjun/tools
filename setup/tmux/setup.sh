#!/bin/bash

install_tmux() {
    echo "Installing tmux..."

    # Check for macOS (Darwin)
    if [[ "$(uname)" == "Darwin" ]]; then
        echo "Detected macOS."
        if command -v brew >/dev/null 2>&1; then
            echo "Installing tmux using Homebrew."
            brew install tmux
        else
            echo "Error: Homebrew not found. Please install Homebrew (https://brew.sh/) or install tmux manually." >&2
            exit 1
        fi

        # Check for Linux
    elif [[ "$(uname)" == "Linux" ]]; then
        echo "Detected Linux."
        if command -v apt >/dev/null 2>&1; then
            echo "Installing tmux using apt (Debian/Ubuntu-based)."
            sudo apt update && sudo apt install -y tmux
        fi
    else
        echo "Error: Unsupported operating system: $(uname)." >&2
        exit 1
    fi

    # Verify installation (optional, but good practice)
    if command -v tmux >/dev/null 2>&1; then
        echo "tmux installed successfully."
    else
        echo "tmux installation might have failed. Please check the logs." >&2
        exit 1
    fi
}

setup_config() {
    local dst=~/.config/tmux
    local project_dir=${dst}/.project

    if [ ! -d "${dst}" ]; then
        echo "Setting up oh-my-tmux configuration..."

        mkdir -p ${dst}
        cd ${dst} && git clone --single-branch https://github.com/gpakosz/.tmux.git ${project_dir}
        ln -s ${project_dir}/.tmux.conf ${dst}/tmux.conf
        # use our tmux.conf.local insteaof default (${project_dir}/.tmux.conf.local)
        cp tmux.conf.local ${dst}/tmux.conf.local

    else
        echo "oh-my-tmux configuration already exists. Skipping setup."
        exit 0
    fi
}

install_tmux
setup_config
