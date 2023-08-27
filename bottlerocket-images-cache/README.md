# Caching Container Images for AWS Bottlerocket Instances
The purpose of this solution is to reduce the boot time of containers on AWS Bottlerocket instances that require large container images by caching the images in the data volume.

Data analytics and machine learning workloads often require container images larger than 1 GiB, which can take up to a minute to pull and extract from ECR. To improve the efficiency of booting these containers, reducing the time to pull the image is key.

[Bottlerocket](https://github.com/bottlerocket-os/bottlerocket) is a Linux-based open-source operating system built by AWS specifically for running containers. It has two volumes, an OS volume and a data volume, with the latter used for storing artifacts and container images. This solution will leverage the data volume to pull images and take snapshots for later usage.

To demonstrate the process of caching images in EBS snapshots and launching them in an EKS cluster, this solution will use Bottlerocket for EKS AMI.

# How it works

![bottlerocket-image-cache drawio](https://user-images.githubusercontent.com/6355087/171136787-ec6b2269-8ebe-404e-acac-b1e4f7f96cd1.png)

1. Launch an EC2 instance with Bottlerocket for EKS AMI, then pull images which need to cache in this EC2.
2. Build the EBS snapshot for the data volume.
3. Launch instance with the EBS snapshot.

# Steps
1. Set up [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-started.html), [eksctl](https://github.com/weaveworks/eksctl) and kubectl in your development environment(Linux or MacOS).
1. Clone this projects in your local environment.
1. Run ```snapshot.sh``` to build the EBS snapshot.
    ```
    ./snapshot.sh -r us-west-2 public.ecr.aws/eks-distro/kubernetes/pause:3.2
    ```
1. Modify ```cluster.sh``` to set CLUSTER_NAME, EBS_SNAPSHOT_ID and AWS_DEFAULT_REGION
1. Run ```cluster.sh``` to build the testing cluster.
1. Run ```kubectl get node``` to list the worker nodes with cached images.
