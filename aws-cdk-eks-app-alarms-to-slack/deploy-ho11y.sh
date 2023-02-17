#!/bin/bash

# exit when any command fails
set -e

NC='\033[0m'       # Text Reset
R='\033[0;31m'          # Red
G='\033[0;32m'        # Green
Y='\033[0;33m'       # Yellow
echo -e "${Y}"

# checking environment variables

if [ -z "${CAP_ACCOUNT_ID}" ]; then
    echo -e "${R}env variable CAP_ACCOUNT_ID not set${NC}"; exit 1
fi

if [ -z "${CAP_CLUSTER_REGION}" ]; then
    echo -e "${R}env variable CAP_CLUSTER_REGION not set${NC}"; exit 1
fi

if [ -z "${CAP_CLUSTER_NAME}" ]; then
    echo -e "${R}env variable CAP_CLUSTER_NAME not set${NC}"; exit 1
fi

if [ -z "${CAP_FUNCTION_NAME}" ]; then
    echo -e "${R}env variable CAP_FUNCTION_NAME not set${NC}"; exit 1
fi

curr_dir=${PWD}

#clone sample application ho11y
git clone https://github.com/aws-observability/aws-o11y-recipes.git
cd ./aws-o11y-recipes/sandbox/ho11y/

#build docker image
docker build . -t "${CAP_ACCOUNT_ID}.dkr.ecr.${CAP_CLUSTER_REGION}.amazonaws.com/ho11y:latest"

#push docker image into ECR repository
aws ecr get-login-password --region ${CAP_CLUSTER_REGION} | \
docker login --username AWS --password-stdin  "${CAP_ACCOUNT_ID}.dkr.ecr.${CAP_CLUSTER_REGION}.amazonaws.com"

aws ecr create-repository --region ${CAP_CLUSTER_REGION} --repository-name ho11y
docker push "${CAP_ACCOUNT_ID}.dkr.ecr.${CAP_CLUSTER_REGION}.amazonaws.com/ho11y:latest"

#create namespace for ho11y application
kubectl create namespace ho11y

# create ho11y-app manifest file and apply
sed -e "s|{{HOLLY_IMAGE}}|${CAP_ACCOUNT_ID}.dkr.ecr.${CAP_CLUSTER_REGION}.amazonaws.com/ho11y:latest|g" ${curr_dir}/templates/ho11y-app-template.yaml > ${curr_dir}/ho11y-app.yaml

kubectl apply -f ${curr_dir}/ho11y-app.yaml
