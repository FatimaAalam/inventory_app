resource "aws_security_group" "app_sg" {
  name        = "launch-wizard-1"
  description = "launch-wizard-1 created 2026-01-28T14:05:37.130Z"
  vpc_id      = "vpc-05e45cf5b3c3f60f8"
  tags        = {}

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["39.34.231.229/32"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "inventory_app" {
  ami                    = "ami-073130f74f5ffb161"
  instance_type          = "t3.small"
  subnet_id              = "subnet-0007532b9109cdae0"
  vpc_security_group_ids = [aws_security_group.app_sg.id]
  key_name               = "SS_KEY"

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name = "Linux_Devops"
  }
}

resource "aws_eip" "inventory_eip" {
  instance = aws_instance.inventory_app.id
  domain   = "vpc"
}
resource "aws_ecr_repository" "inventory_app" {
  name                 = "inventory-app"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}
# --- GitHub OIDC Provider ---
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# --- IAM Role assumed by GitHub Actions ---
resource "aws_iam_role" "github_actions_ecr" {
  name = "github-actions-ecr-push"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:FatimaAalam/inventory_app:*"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "github_actions_ecr_push" {
  name = "ecr-push-policy"
  role = aws_iam_role.github_actions_ecr.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRAuth"
        Effect = "Allow"
        Action = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid    = "ECRPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:BatchGetImage"
        ]
        Resource = aws_ecr_repository.inventory_app.arn
      }
    ]
  })
}
