SHELL :=/bin/bash

ARCH=$(shell uname -m)

ifeq ($(ARCH), x86_64)
       ARCH=amd64
endif

export DOCKER_BUILDKIT=1

# Taken from: https://www.cmcrossroads.com/article/printing-value-makefile-variable
print-%  : ; @echo $($*)

.PHONY: help
help: ## Show make targets
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

.PHONY: vim
vim: ## build container for vim
	cd vim && docker build \
		--build-arg UID=$(shell id -u) \
		--build-arg GID=$(shell id -g) \
		--build-arg USER=${USER} \
		--build-arg ARCH=${ARCH} \
		-t vim .
