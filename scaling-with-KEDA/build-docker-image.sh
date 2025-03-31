#!/usr/bin/env bash

echo "AWS Region" $CW_AWS_REGION
echo "HO11Y Repo" $CW_HO11Y_ECR
echo "HO11Y Image :" $CW_HO11Y_IMAGE

if [ -z "$CW_AWS_REGION" ]; then
  echo "\CW_AWS_REGION environement variable is empty."
  exit 1
fi

if [ -z "$CW_HO11Y_ECR" ]; then
  echo "\CW_HO11Y_ECR environement variable is empty."
  exit 1
fi

if [ -z "$CW_HO11Y_IMAGE" ]; then
  echo "\CW_HO11Y_IMAGE environement variable is empty."
  exit 1
fi

git clone https://github.com/aws-observability/aws-o11y-recipes.git 
cd ./aws-o11y-recipes/sandbox/ho11y/

docker build . -t "$CW_HO11Y_IMAGE"

aws ecr get-login-password \
  --region $CW_AWS_REGION | docker login \
  --username AWS \
  --password-stdin "$CW_HO11Y_ECR" 
  
 aws ecr create-repository \
 --repository-name ho11y  \
 --region $CW_AWS_REGION

docker push "$CW_HO11Y_IMAGE"