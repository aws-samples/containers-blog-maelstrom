#!/bin/bash

IMAGE_REPO ?= ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
IMAGE_NAME ?= ${ECR_REPO}
IMAGE_TAG ?= latest


PWD := $(shell pwd)
BASE_DIR := $(shell basename $(PWD))

# Keep an existing GOPATH, make a private one if it is undefined
GOPATH_DEFAULT := $(PWD)/.go
export GOPATH ?= $(GOPATH_DEFAULT)
TESTARGS_DEFAULT := "-v"
export TESTARGS ?= $(TESTARGS_DEFAULT)
DEST := $(GOPATH)/src/$(GIT_HOST)/$(BASE_DIR)





LOCAL_OS := $(shell uname)
ifeq ($(LOCAL_OS),Linux)
    TARGET_OS ?= linux
    XARGS_FLAGS="-r"
else ifeq ($(LOCAL_OS),Darwin)
    TARGET_OS ?= darwin
    XARGS_FLAGS=
else
    $(error "This system's OS $(LOCAL_OS) isn't recognized/supported")
endif

all: build-linux image

ifeq (,$(wildcard go.mod))
ifneq ("$(realpath $(DEST))", "$(realpath $(PWD))")
    $(error Please run 'make' from $(DEST). Current directory is $(PWD))
endif
endif


############################################################
# build section
############################################################

build-linux:
	@echo "Building the $(IMAGE_NAME) binary for Docker (linux)..."
	@GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o ./output/$(IMAGE_NAME) ./src/

############################################################
# image section
############################################################

image: build-image push-image

build-image: build-linux
	@echo "Building the docker image: $(IMAGE_NAME):$(IMAGE_TAG)..."
	@docker build --no-cache -t  $(IMAGE_REPO)/$(IMAGE_NAME):$(IMAGE_TAG) .

push-image: build-image
	@echo "Pushing the docker image for $(IMAGE_REPO)/$(IMAGE_NAME):$(IMAGE_TAG) ..."	
	aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin $(IMAGE_REPO)/$(IMAGE_NAME)
	@docker push $(IMAGE_REPO)/$(IMAGE_NAME):$(IMAGE_TAG)
	

############################################################
# clean section
############################################################
clean:
	@rm -rf output

.PHONY: all build image clean


logs:
	kubectl logs -f -lapp=custom-kube-scheduler-webhook  -n custom-kube-scheduler-webhook 