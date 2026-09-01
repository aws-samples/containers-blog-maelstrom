#!/bin/bash

export LABEL1="on-demand"
export LABEL2="spot"

export NAMESPACE="test"

kubectl get pod -n $NAMESPACE
PODS=$(kubectl get pod -n $NAMESPACE | wc -l)
PODS=$((PODS-1))
echo "Number of Pods in namespace $NAMESPACE is $PODS"
L1=$(kubectl get pods -n $NAMESPACE -l app=nginx -o jsonpath='{.items[*].spec.nodeSelector}' | grep  -o  $LABEL1 | wc -l)
echo "Number of Pods for $LABEL1 is $L1"
L2=$(kubectl get pods -n $NAMESPACE -l app=nginx -o jsonpath='{.items[*].spec.nodeSelector}' | grep  -o  $LABEL2 | wc -l)
echo "Number of Pods for $LABEL2 is $L2"