## pre-dfined env
# arch
ARG ARCH=amd64
# user
ARG UID=1000
ARG GID=1000
ARG USER=ubuntu
# go
ARG GO_VERSION=1.20.4
ARG WK_DIR=/Workspace


FROM ubuntu:latest
# take args in
ARG UID
ARG GID
ARG USER
ARG ARCH
ARG GO_VERSION
ARG WK_DIR

## set up for system
# pkg
RUN \
  apt-get update && apt-get install -y \
  vim \
  git \
  curl \
  wget \
  build-essential \
  python3-dev \
  cmake \
  sudo \
  ripgrep \
  locales \
  && locale-gen en_US.UTF-8 \
  && rm -rf /var/lib/apt/lists/*

# golang
RUN \
  wget https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz -P /tmp \
  && rm -rf /usr/local/go && tar -C /usr/local -xzf /tmp/go${GO_VERSION}.linux-${ARCH}.tar.gz \
  && rm -rf /tmp/*

# set up for developer (workaround for executing sudo)
RUN \
  getent group $GID || groupadd -g $GID $USER \
  && useradd -m -s /bin/bash -u $UID -g $GID -G sudo $USER \
  && echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

## vim for user
USER $USER
COPY --chown=$UID:$GID vimrc /home/$USER/.vimrc
ENV PATH=$PATH:/usr/local/go/bin

# install plug (vim -c 'PlugInstall --sync' -c qa => vim +'PlugInstall --sync' +qa) and necessary for plugin
RUN \
  curl -fLo ~/.vim/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim \
  && vim -f -c 'PlugInstall' -c "qa!" \
  && python3 /home/$USER/.vim/plugged/YouCompleteMe/third_party/ycmd/build.py --clang-completer --go-completer --rust-completer --verbose \
  && vim +'GoInstallBinaries' +'qa'

# set env (亂碼)
RUN \
  echo "export LC_ALL=en_US.UTF-8" >> /home/$USER/.bashrc \
  && echo "export GOPATH=/home/$USER/go" >> /home/$USER/.bashrc \
  && echo 'export PATH=$PATH:/usr/local/go/bin:$(go env GOPATH)/bin' >> /home/$USER/.bashrc

WORKDIR $WK_DIR
