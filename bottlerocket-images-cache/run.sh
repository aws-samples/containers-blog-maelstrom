#!/bin/bash
#aws ecr list-images --repository-name=sd-gen-webui-automatic1111 --query 'sort_by(imageDetails,& imagePushedAt)[*]'
#aws ecr describe-images --repository-name=sd-gen-webui-automatic1111 --query 'sort_by(imageDetails,& imagePushedAt)[*]'


export IMAGE_TAG=$(aws ecr describe-images --output json --repository-name $ECR_REPOSITORY --query 'sort_by(imageDetails,& imagePushedAt)[-1].imageTags[0]' | jq . --raw-output)
echo 'IMAGE_URL:' "$ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG"

. ./snapshot.sh -r ap-northeast-1 $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG
echo 'done 2 SNAPSHOT_ID: ' $SNAPSHOT_ID
# set to github action
# https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions#environment-files
echo "IMAGE_TAG=$IMAGE_TAG" >> "$GITHUB_ENV"
echo "SNAPSHOT_ID=$SNAPSHOT_ID" >> "$GITHUB_ENV"

