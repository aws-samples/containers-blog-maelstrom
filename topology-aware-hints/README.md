# Topology aware hints demo

This code is used to demostrate usage of `TopologyAwareHints` introduced on Kubernetes 1.24.

## What's included

* An Amazon EKS cluster
* AWS Distro for OpenTelemetry (ADOT) Operator
* Sample Application

## Prerequisites

* Basic understanding of Linux operating systems and Kubernetes.
* An AWS account.
* Administrator or equivalent access to deploy the required resources.
* AWS Command Line Interface (AWS CLI) (v2.6.3+) installed and configured.
* Terraform CLI installed
* `git` CLI installed
* `kubectl`, and `helm` client installed

## Deploy

Run the following command to deploy the cluster. Replace ap-southeast-1 to your Region. This process may take 20–30 minutes.

```bash
export AWS_REGION="ap-southeast-1"
terraform init
terraform plan
terraform apply -auto-approve
```

Once the Terraform has completed, then you can set up kubectl by running this command:

```bash
aws eks --region $AWS_REGION update-kubeconfig --name tah-demo-cluster
```

Run the following command to deploy the sample application:

```bash
cd ../kubernetes
kubectl apply --server-side -f common.yaml
kubectl apply --server-side -f simple.yaml
```

Get the endpoint for user interface (UI) component by running the following command:

```bash
kubectl get svc ui-lb -n ui -o jsonpath={.status.loadBalancer.ingress[0].hostname}
```

You can access the demo application by accessing `http://<link>/home`. This displays an example online shopping site.
