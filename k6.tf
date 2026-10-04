#------------------------------------------------------------------------------
# k6 Load Test Instance — TEMPORARY
# Delete this file (or `terraform destroy -target`) when load testing is done.
#------------------------------------------------------------------------------

data "aws_ami" "k6_al2023_arm" {
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

resource "aws_security_group" "k6" {
  name        = "${var.project_name}-${var.environment}-k6-sg"
  description = "k6 load test instance (temporary)"
  vpc_id      = module.networking.vpc_id

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-k6-sg"
  }
}

# Open API SG :18080 to k6 SG — Spring direct, bypassing Nginx.
# aws_vpc_security_group_ingress_rule coexists safely with the inline ingress
# blocks in modules/networking under provider v5.
resource "aws_vpc_security_group_ingress_rule" "api_from_k6" {
  security_group_id            = module.networking.ec2_security_group_id
  referenced_security_group_id = aws_security_group.k6.id
  ip_protocol                  = "tcp"
  from_port                    = 18080
  to_port                      = 18080
  description                  = "Spring direct (18080) from k6 load test instance"

  tags = {
    Name = "${var.project_name}-${var.environment}-api-from-k6"
  }
}

resource "aws_iam_role" "k6" {
  name = "${var.project_name}-${var.environment}-k6-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-k6-role"
  }
}

resource "aws_iam_role_policy_attachment" "k6_ssm" {
  role       = aws_iam_role.k6.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "k6" {
  name = "${var.project_name}-${var.environment}-k6-profile"
  role = aws_iam_role.k6.name
}

resource "aws_instance" "k6" {
  ami                         = data.aws_ami.k6_al2023_arm.id
  instance_type               = "c6g.large"
  subnet_id                   = module.networking.public_subnet_id
  vpc_security_group_ids      = [aws_security_group.k6.id]
  iam_instance_profile        = aws_iam_instance_profile.k6.name
  associate_public_ip_address = true

  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true

    tags = {
      Name = "${var.project_name}-${var.environment}-k6-root"
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = <<-EOF
    #!/bin/bash
    set -eux
    dnf install -y tar gzip git
    K6_VERSION=v0.55.0
    cd /tmp
    curl -fsSL "https://github.com/grafana/k6/releases/download/$${K6_VERSION}/k6-$${K6_VERSION}-linux-arm64.tar.gz" -o k6.tgz
    tar -xzf k6.tgz
    install -m 0755 "k6-$${K6_VERSION}-linux-arm64/k6" /usr/local/bin/k6
    rm -rf k6.tgz "k6-$${K6_VERSION}-linux-arm64"
  EOF

  tags = {
    Name = "${var.project_name}-${var.environment}-k6"
  }
}

output "k6_instance_id" {
  description = "k6 load test instance ID"
  value       = aws_instance.k6.id
}

output "k6_public_ip" {
  description = "k6 instance public IP"
  value       = aws_instance.k6.public_ip
}

output "k6_ssm_command" {
  description = "Start an SSM session into the k6 instance"
  value       = "aws ssm start-session --target ${aws_instance.k6.id} --region ${var.aws_region}"
}

output "k6_target_api_internal" {
  description = "Direct Spring endpoint (bypasses Nginx)"
  value       = "http://${module.ec2.instance_private_ip}:18080"
}
