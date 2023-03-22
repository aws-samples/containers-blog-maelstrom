import json
import boto3
import time
import logging

eks = boto3.client('eks')
autoscaling = boto3.client('autoscaling')

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    ASG_METRICS_COLLLECTION_TAG_NAME = "ASG_METRICS_COLLLECTION_ENABLED"
    initial_retry_delay = 10
    attempts = 0 
    
    #print(event)
    
    if not event["detail"]["eventName"] == "CreateNodegroup":
        print("invalid event.")
        return -1
        
    
        
    clusterName = event["detail"]["requestParameters"]["name"]
    nodegroupName = event["detail"]["requestParameters"]["nodegroupName"]
    try:
        metricsCollectionEnabled = event["detail"]["requestParameters"]["tags"][ASG_METRICS_COLLLECTION_TAG_NAME]
    except KeyError:
        print(ASG_METRICS_COLLLECTION_TAG_NAME, "tag not found.")
        return
    
    # Check if metrics collection is enabled in tags
    if metricsCollectionEnabled.lower() != "true":
        print("Metrics collection is not enabled in nodegroup tags.")
        return
    
    # Get the name of the associated autoscaling group
    print("Getting the autoscaling group name for nodegroup=", nodegroupName, ", cluster=", clusterName )
    for i in range(0,10):
        try:
            autoScalingGroup = eks.describe_nodegroup(clusterName=clusterName,nodegroupName=nodegroupName)["nodegroup"]["resources"]["autoScalingGroups"][0]["name"]
        except:
            attempts += 1
            print("Failed to obtain the associated autoscaling group for nodegroup", nodegroupName, "Retrying in", initial_retry_delay*attempts, "seconds.")
            time.sleep(initial_retry_delay*attempts)
        else:
            break
    
    print("Enabling metrics collection on autoscaling group ", autoScalingGroup)
    
    # Enable metrics collection in the autoscaling group
    try:
        enableMetricsCollection = autoscaling.enable_metrics_collection(AutoScalingGroupName=autoScalingGroup,Granularity="1Minute")
    except:
        print("Unable to enable metrics collection on nodegroup=",nodegroup)
    print("Enabled metrics collection on nodegroup", nodegroupName)
