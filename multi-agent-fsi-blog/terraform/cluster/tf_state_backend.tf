# -----------------------------------------------------------------------------
# Remote Terraform state backend for the in-cluster Tofu Controller.
#
# Why this exists:
#   Tofu Controller's default Kubernetes state backend stores Terraform state
#   in a Secret that is only written when the runner Pod exits cleanly. If the
#   runner is SIGKILL'd (OOM, node consolidation, controller restart) while
#   `terraform apply` is in-flight, state becomes inconsistent — Tofu will
#   happily re-create already-provisioned AWS resources on the next reconcile,
#   producing EntityAlreadyExists / ResourceInUseException loops that only
#   clear by manually deleting the orphan AWS resources.
#
# The S3 backend with DynamoDB locking is the battle-tested fix. State is
# durable across Pod restarts; lock acquisition blocks concurrent applies.
# -----------------------------------------------------------------------------

resource "random_id" "tfstate_suffix" {
  byte_length = 4
}

locals {
  tfstate_bucket     = "${var.cluster_name}-tfstate-${random_id.tfstate_suffix.hex}"
  tfstate_lock_table = "${var.cluster_name}-tfstate-locks"
}

resource "aws_s3_bucket" "tfstate" {
  bucket        = local.tfstate_bucket
  force_destroy = true

  tags = local.tags
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "tfstate_locks" {
  name         = local.tfstate_lock_table
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = local.tags
}

# Grant the tf-runner role the permissions it needs to use the S3 backend.
# This extends the inline policy we already have on aws_iam_role.tf_runner.
resource "aws_iam_role_policy" "tf_runner_s3_backend" {
  name = "${local.tf_runner_role_name}-s3-backend"
  role = aws_iam_role.tf_runner.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "StateBucketAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
        ]
        Resource = [
          aws_s3_bucket.tfstate.arn,
          "${aws_s3_bucket.tfstate.arn}/*",
        ]
      },
      {
        Sid    = "StateLockAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:DescribeTable",
        ]
        Resource = aws_dynamodb_table.tfstate_locks.arn
      },
    ]
  })
}
