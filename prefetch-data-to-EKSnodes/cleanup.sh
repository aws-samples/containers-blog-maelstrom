#!/bin/bash

# Delete Pod

echo ****** Deleting  Pod *****

kubectl delete pod $EDP_NAME

# Delete Node Group

echo ****** Deleting EKS NodeGroup *****

eksctl delete nodegroup --cluster=$EDP_NAME --name=nodegroup

# Delete EKS Cluster

echo ***** Deleting EKS Cluster *****

eksctl delete cluster --name=$EDP_NAME --region $EDP_AWS_REGION

# Delete State Manager Association

echo ***** Deleting AWS Systems Manager State Manager Association *****

association_id=$(aws ssm list-associations --association-filter-list key=Name,value=AWS-RunShellScript --query "Associations[0].AssociationId" --region $EDP_AWS_REGION --output text)

if [ -z "$association_id" ]; then
  echo "No association found for document $document_name."
  exit 1
fi

aws ssm delete-association --association-id $association_id --region $EDP_AWS_REGION

# Delete EventBridge Rule along with Target attached to it

# Get the targets of the rule

echo ***** Deleting EventBridge Target *****

TARGETS=$(aws events list-targets-by-rule --rule $EDP_NAME --region $EDP_AWS_REGION | jq -r '.Targets[].Id')

# Remove each target from the rule

for target in $TARGETS; do
  aws events remove-targets --rule $EDP_NAME --ids $target --region $EDP_AWS_REGION
done

# Delete the rule

echo ***** Deleting EventBridge Rule *****

aws events delete-rule --name $EDP_NAME --region $EDP_AWS_REGION

# Delete the role we created for EventBridge Rule

echo ***** Deleting Role and Policy we created for EventBridge Rule *****

aws iam delete-role-policy --role-name ${EDP_NAME}-role --policy-name ${EDP_NAME}-policy
aws iam delete-role --role-name ${EDP_NAME}-role

# Delete ECR Repo

echo ***** Deleting ECR Repo *****

aws ecr delete-repository --repository-name $EDP_NAME --force --region $EDP_AWS_REGION

# Delete Docker Image and files folder that we created in order to create large Docker Image

echo ***** Deleting Docker Image and Files Folder *****

docker rmi $EDP_NAME
docker rmi $EDP_AWS_ACCOUNT.dkr.ecr.$EDP_AWS_REGION.amazonaws.com/$EDP_NAME
rm -rf files
