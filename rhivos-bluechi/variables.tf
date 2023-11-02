variable "ami_id_x86" {
  type        = string
  description = "The id of RHIVOS AMI"
  default      = "ami-08221099381170177"
}

variable "key_name" {
  type         = string
  description  = "EC2 key pair for SSH"
  default      = "AWS_EAST2"
}

variable "instance_type" {
  type         = string
  description  = "EC2 instance type"
  default      = "t3a.nano"
}

variable "aws_region" {
  type         = string
  description  = "AWS Region"
  default      = "us-east-2"
}

variable "ami_prefix" {
  type         = string
  description  = "AutoSD AMI prefix"
  default      = "auto-osbuild-aws*"
}

variable "cidr_block" {
  type         = string
  description  = "CIDR block"
  default      = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  type         = string
  description  = "Public CIDR block"
  default      = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  type         = string
  description  = "Private CIDR block"
  default      = "10.0.2.0/24"
}
