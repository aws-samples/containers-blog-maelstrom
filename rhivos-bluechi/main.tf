terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region  = var.aws_region
}


data "aws_ami" "autosd_ami_id_x86" {
  most_recent  = true
  owners       = [var.ami_owner_account_id]
  filter {
    name   = "name"
    values = [var.ami_prefix]
  }

  filter {
    name = "architecture"
    values = ["x86_64"]
  }
}

data "aws_ami" "autosd_ami_id_arm64" {
  most_recent  = true
  owners       = [var.ami_owner_account_id]
  filter {
    name   = "name"
    values = [var.ami_prefix]
  }

  filter {
    name = "architecture"
    values = ["arm64"]
  }
}

data "http" "my_ip" {
  url = "http://checkip.amazonaws.com"
}


resource "aws_vpc" "autosd_demo_vpc" {
  cidr_block           = var.cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "autosd-demo-vpc"
  }
}

resource "aws_subnet" "autosd_demo_subnet_public" {
  vpc_id            = aws_vpc.autosd_demo_vpc.id
  cidr_block        = var.public_subnet_cidr
  availability_zone = "us-east-2a"

  tags = {
    Name = "autosd-demo-subnet-public"
  }
}

resource "aws_subnet" "autosd_demo_subnet_private" {
  vpc_id            = aws_vpc.autosd_demo_vpc.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = "us-east-2a"

  tags = {
    Name = "autosd-demo-subnet-private"
  }
}

resource "aws_internet_gateway" "autosd_demo_ig" {
  vpc_id = aws_vpc.autosd_demo_vpc.id

  tags = {
    Name = "autosd-demo-ig"
  }
}

resource "aws_route_table" "autosd_demo_rt" {
  vpc_id = aws_vpc.autosd_demo_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.autosd_demo_ig.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.autosd_demo_ig.id
  }

  tags = {
    Name = "autosd-demo-rt"
  }
}

resource "aws_route_table_association" "public_1_rt_a" {
  subnet_id      = aws_subnet.autosd_demo_subnet_public.id
  route_table_id = aws_route_table.autosd_demo_rt.id
}

resource "aws_security_group" "autosd_demo_sg" {
  name   = "autosd-demo-sg"
  vpc_id = aws_vpc.autosd_demo_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    self        = true
    cidr_blocks = ["${chomp(data.http.my_ip.response_body)}/32"]

  }

  ingress {
    from_port   = 2020
    to_port     = 2020
    protocol    = "tcp"
    self        = true
  }
  
  ingress {
   from_port   = 80
   to_port     = 80
   protocol    = "tcp"
   self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_role" "autosd_instance_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

data "aws_iam_policy" "ec2_read_only_policy" {
  name = "AmazonEC2ReadOnlyAccess"
}

data "aws_iam_policy" "autoscaling_read_only_policy" {
  name = "AutoScalingReadOnlyAccess"
}

data "aws_iam_policy" "amazonssm_managed_instance_core_policy" {
  name = "AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ssm_policy_attachment" {
  policy_arn = data.aws_iam_policy.amazonssm_managed_instance_core_policy.arn
  role       = aws_iam_role.autosd_instance_role.name
}

resource "aws_iam_role_policy_attachment" "ec2_policy_attachment" {
  policy_arn = data.aws_iam_policy.ec2_read_only_policy.arn
  role       = aws_iam_role.autosd_instance_role.name
}

resource "aws_iam_role_policy_attachment" "autoscaling_policy_attachment" {
  policy_arn = data.aws_iam_policy.autoscaling_read_only_policy.arn
  role       = aws_iam_role.autosd_instance_role.name
}

resource "aws_iam_instance_profile" "autosd_instance_profile" {
  #name = "autosd_instance_profile"
  role = aws_iam_role.autosd_instance_role.name
}

resource "aws_launch_template" "autosd_x86_launch_template" {
  name_prefix   = "autosd_launch_template-"
  image_id      = data.aws_ami.autosd_ami_id_x86.id
  instance_type = "t3a.nano"
  key_name      = var.key_name
  iam_instance_profile {
    name = aws_iam_instance_profile.autosd_instance_profile.name
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups = [aws_security_group.autosd_demo_sg.id]
  }

  # x86 node is used as the manager node
  user_data = filebase64("configure-bluechi-controller.sh")
}

resource "aws_launch_template" "autosd_arm64_launch_template" {
  name_prefix   = "autosd_launch_template-"
  image_id      = data.aws_ami.autosd_ami_id_arm64.id
  instance_type = "t4g.nano"
  key_name      = var.key_name
  iam_instance_profile {
    name = aws_iam_instance_profile.autosd_instance_profile.name
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups = [aws_security_group.autosd_demo_sg.id]
  }

  # Arm nodes are used as agent nodes
  user_data = filebase64("configure-bluechi-agent.sh")
}

resource "aws_autoscaling_group" "autosd_demo_asg_manager" {
  name_prefix                 = "autosd_demo-asg-manager"
  launch_template {
    id      = aws_launch_template.autosd_x86_launch_template.id
    version = "$Latest"
  }
  vpc_zone_identifier         = [aws_subnet.autosd_demo_subnet_public.id]
  min_size                    = 1
  max_size                    = 1
  desired_capacity            = 1
  health_check_type           = "EC2"
  termination_policies        = ["OldestLaunchConfiguration"]
  tag {
    key                 = "Name"
    value               = "AutoSD_Manager"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_group" "autosd_demo_asg_managed_node" {
  name_prefix                 = "autosd_demo-asg-managed_nodes"
  launch_template {
    id      = aws_launch_template.autosd_arm64_launch_template.id
    version = "$Latest"
  }
  vpc_zone_identifier         = [aws_subnet.autosd_demo_subnet_public.id]
  min_size                    = 1
  max_size                    = 1
  desired_capacity            = 1
  health_check_type           = "EC2"
  termination_policies        = ["OldestLaunchConfiguration"]
  tag {
    key                 = "Name"
    value               = "AutoSD_Managed_Node"
    propagate_at_launch = true
  }
}
