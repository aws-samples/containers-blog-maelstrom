#!/bin/bash


sleep 1
export POD_NAME=$(kubectl get pods -n custom-kube-scheduler-webhook -l app=custom-kube-scheduler-webhook -o jsonpath='{.items[].metadata.name}')
kubectl logs -f $POD_NAME -n custom-kube-scheduler-webhook

