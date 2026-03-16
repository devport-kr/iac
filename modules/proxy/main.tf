#------------------------------------------------------------------------------
# Data Sources
#------------------------------------------------------------------------------

# Get latest Amazon Linux 2023 ARM AMI
data "aws_ami" "amazon_linux_2023_arm" {
  count       = var.ami_id == "" ? 1 : 0
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-arm64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

#------------------------------------------------------------------------------
# IAM Role for Proxy EC2
# Permissions for:
# - SSM (Session Manager access)
# - Route53 (certbot DNS-01 challenge)
#------------------------------------------------------------------------------
resource "aws_iam_role" "proxy" {
  name = "${var.project_name}-${var.environment}-proxy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-proxy-role"
  }
}

resource "aws_iam_instance_profile" "proxy" {
  name = "${var.project_name}-${var.environment}-proxy-profile"
  role = aws_iam_role.proxy.name
}

# SSM for Session Manager
resource "aws_iam_role_policy_attachment" "proxy_ssm" {
  role       = aws_iam_role.proxy.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Route53 for certbot DNS-01 challenge
resource "aws_iam_role_policy" "proxy_route53_certbot" {
  name = "${var.project_name}-${var.environment}-proxy-route53-certbot"
  role = aws_iam_role.proxy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:GetChange"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets"
        ]
        Resource = "arn:aws:route53:::hostedzone/*"
      }
    ]
  })
}

#------------------------------------------------------------------------------
# Proxy EC2 Instance
#------------------------------------------------------------------------------
resource "aws_instance" "proxy" {
  ami                    = var.ami_id != "" ? var.ami_id : data.aws_ami.amazon_linux_2023_arm[0].id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  iam_instance_profile   = aws_iam_instance_profile.proxy.name

  user_data = base64encode(templatefile("${path.module}/templates/user_data.sh", {
    api_domain    = var.api_domain
    backend_ip    = var.backend_ip
    certbot_email = var.certbot_email
  }))

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 required
    http_put_response_hop_limit = 1
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-proxy"
  }

  lifecycle {
    ignore_changes = [ami, user_data]
  }
}

#------------------------------------------------------------------------------
# Elastic IP for Proxy
#------------------------------------------------------------------------------
resource "aws_eip" "proxy" {
  instance = aws_instance.proxy.id
  domain   = "vpc"

  tags = {
    Name = "${var.project_name}-${var.environment}-proxy-eip"
  }
}
