#!/bin/bash -xs

IMAGE_REPO ?= ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
IMAGE_NAME ?= ${BOOTSTRAP_ECR_REPO}

IMAGE_TAG ?= latest
PLATFORM ?= linux/amd64

PWD := $(shell pwd)
BASE_DIR := $(shell basename $(PWD))


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

all: image

############################################################
# image section
############################################################

image: build-image push-image

build-image:
	@echo "Building the container image (platform: $(PLATFORM)): $(IMAGE_NAME):$(IMAGE_TAG) using ${BOOTSTRAP_ECR_REPO}/Dockerfile..."
	@docker build --platform $(PLATFORM) --no-cache -t $(IMAGE_REPO)/$(IMAGE_NAME):$(IMAGE_TAG) .

push-image: build-image
	@echo "Pushing the container image (platform: $(PLATFORM)) for $(IMAGE_REPO)/$(IMAGE_NAME):$(IMAGE_TAG) ..."
	aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin $(IMAGE_REPO)/$(IMAGE_NAME)
	@docker push $(IMAGE_REPO)/$(IMAGE_NAME):$(IMAGE_TAG)


############################################################
# clean section
############################################################
clean:
	@rm -rf output

.PHONY: all build image clean
