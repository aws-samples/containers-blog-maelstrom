#!/bin/bash

tag=$(aws ecr describe-images --repository-name $EDP_NAME --query 'sort_by(imageDetails,& imagePushedAt)[-1].imageTags[0]' --output text)

echo $tag

cat << EOF > pod.yaml
---
apiVersion: v1
kind: Pod
metadata:
  name: $EDP_NAME
spec:
  containers:
  - name: $EDP_NAME
    image: $EDP_AWS_ACCOUNT.dkr.ecr.$EDP_AWS_REGION.amazonaws.com/$EDP_NAME:$tag
    imagePullPolicy: Always
    command: ["sleep", "3600"]
EOF
