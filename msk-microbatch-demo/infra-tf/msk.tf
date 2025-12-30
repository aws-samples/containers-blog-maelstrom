module "msk_cluster" {
  source  = "terraform-aws-modules/msk-kafka-cluster/aws"
  version = "~> 2.0"

  name                   = "msk-demo-cluster"
  kafka_version          = "3.6.0"
  number_of_broker_nodes = local.msk_broker_count

  broker_node_client_subnets  = module.vpc.private_subnets
  broker_node_instance_type   = "kafka.m5.large"
  broker_node_security_groups = [aws_security_group.msk.id]

  client_authentication = {
    sasl = { iam = true }
  }

  encryption_in_transit_client_broker = "TLS"
  encryption_in_transit_in_cluster    = true

  jmx_exporter_enabled    = true
  node_exporter_enabled   = true
  cloudwatch_logs_enabled = true

  configuration_name        = "${local.name}-msk-config"
  configuration_description = "MSK configuration for demo"
  configuration_server_properties = {
    "auto.create.topics.enable"  = true
    "default.replication.factor" = local.msk_broker_count
    "num.partitions"             = local.msk_partition_count
  }

  tags = local.tags
}

resource "aws_security_group" "msk" {
  name   = "${local.name}-msk-sg"
  vpc_id = module.vpc.vpc_id

  # Kafka traffic
  ingress {
    from_port   = 9098
    to_port     = 9098
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr]
    description = "MSK IAM auth"
  }

  # Prometheus JMX Exporter
  ingress {
    from_port   = 11001
    to_port     = 11001
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr]
    description = "MSK JMX Exporter"
  }

  # Prometheus Node Exporter
  ingress {
    from_port   = 11002
    to_port     = 11002
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr]
    description = "MSK Node Exporter"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}

# IAM policy for Kafka consumer app
resource "aws_iam_policy" "msk_consumer_policy" {
  name = "${local.name}-msk-consumer-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kafka-cluster:Connect",
          "kafka-cluster:AlterCluster",
          "kafka-cluster:DescribeCluster"
        ]
        Resource = module.msk_cluster.arn
      },
      {
        Effect = "Allow"
        Action = [
          "kafka-cluster:*Topic*",
          "kafka-cluster:WriteData",
          "kafka-cluster:ReadData"
        ]
        Resource = "arn:aws:kafka:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:topic/${module.msk_cluster.cluster_name}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "kafka-cluster:AlterGroup",
          "kafka-cluster:DescribeGroup"
        ]
        Resource = "arn:aws:kafka:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:group/${module.msk_cluster.cluster_name}/*"
      }
    ]
  })

  tags = local.tags
}

# IAM policy for Kafka producer app
resource "aws_iam_policy" "msk_producer_policy" {
  name = "${local.name}-msk-producer-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kafka-cluster:Connect",
          "kafka-cluster:AlterCluster",
          "kafka-cluster:DescribeCluster"
        ]
        Resource = module.msk_cluster.arn
      },
      {
        Effect = "Allow"
        Action = [
          "kafka-cluster:*Topic*",
          "kafka-cluster:WriteData",
          "kafka-cluster:ReadData"
        ]
        Resource = "arn:aws:kafka:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:topic/${module.msk_cluster.cluster_name}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "kafka-cluster:AlterGroup",
          "kafka-cluster:DescribeGroup"
        ]
        Resource = "arn:aws:kafka:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:group/${module.msk_cluster.cluster_name}/*"
      }
    ]
  })

  tags = local.tags
}

# IAM policy for KEDA operator - allow ALL
resource "aws_iam_policy" "keda_msk_policy" {
  name = "${local.name}-keda-msk-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "kafka-cluster:*"
        Resource = "*"
      }
    ]
  })

  tags = local.tags
}

# # IAM policy for KEDA operator
# resource "aws_iam_policy" "keda_msk_policy" {
#   name = "${local.name}-keda-msk-policy"

#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow"
#         Action = [
#           "kafka-cluster:Connect",
#           "kafka-cluster:AlterCluster",
#           "kafka-cluster:DescribeCluster"
#         ]
#         Resource = module.msk_cluster.arn
#       },
#       {
#         Effect = "Allow"
#         Action = [
#           "kafka-cluster:*Topic*",
#           "kafka-cluster:WriteData",
#           "kafka-cluster:ReadData"
#         ]
#         Resource = "arn:aws:kafka:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:topic/${module.msk_cluster.cluster_name}/*"
#       },
#       {
#         Effect = "Allow"
#         Action = [
#           "kafka-cluster:AlterGroup",
#           "kafka-cluster:DescribeGroup"
#         ]
#         Resource = "arn:aws:kafka:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:group/${module.msk_cluster.cluster_name}/*"
#       }
#     ]
#   })

#   tags = local.tags
# }

# Pod Identity for Kafka producer
module "kafka_producer_pod_identity" {
  source = "terraform-aws-modules/eks-pod-identity/aws"

  name = "${local.name}-producer"

  additional_policy_arns = {
    msk_producer = aws_iam_policy.msk_producer_policy.arn
  }

  associations = {
    producer = {
      cluster_name    = module.eks.cluster_name
      namespace       = "default"
      service_account = "producer-sa"
    }
  }

  tags = local.tags
}

# Pod Identity for Kafka consumer
module "kafka_consumer_pod_identity" {
  source = "terraform-aws-modules/eks-pod-identity/aws"

  name = "${local.name}-consumer"

  additional_policy_arns = {
    msk_consumer = aws_iam_policy.msk_consumer_policy.arn
  }

  associations = {
    consumer = {
      cluster_name    = module.eks.cluster_name
      namespace       = "default"
      service_account = "consumer-sa"
    }
  }

  tags = local.tags
}


