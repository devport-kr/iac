#------------------------------------------------------------------------------
# Network Load Balancer
#------------------------------------------------------------------------------
resource "aws_lb" "api" {
  name               = "${var.project_name}-${var.environment}-nlb"
  internal           = false
  load_balancer_type = "network"
  subnets            = [var.subnet_id]

  enable_cross_zone_load_balancing = true
  enable_deletion_protection       = var.environment == "prod" ? true : false

  tags = {
    Name = "${var.project_name}-${var.environment}-nlb"
  }
}

#------------------------------------------------------------------------------
# Target Group
#------------------------------------------------------------------------------
resource "aws_lb_target_group" "api" {
  name_prefix = "dptg-"
  port        = 8080
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = "/actuator/health/readiness"
    port                = "8080"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
  }

  # Preserve client IP for nginx access logs
  preserve_client_ip = true

  # Deregistration delay
  deregistration_delay = 30

  tags = {
    Name = "${var.project_name}-${var.environment}-tg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

#------------------------------------------------------------------------------
# Target Group Attachment
#------------------------------------------------------------------------------
resource "aws_lb_target_group_attachment" "api" {
  target_group_arn = aws_lb_target_group.api.arn
  target_id        = var.ec2_instance_id
  port             = 8080
}

#------------------------------------------------------------------------------
# Listener (TLS 443)
#------------------------------------------------------------------------------
resource "aws_lb_listener" "api" {
  load_balancer_arn = aws_lb.api.arn
  port              = 443
  protocol          = "TLS"
  certificate_arn   = var.certificate_arn
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-listener"
  }
}

#------------------------------------------------------------------------------
# HTTP to HTTPS Redirect Listener (Optional)
# Note: NLB doesn't do HTTP redirects natively, so we forward to nginx
# which handles the redirect
#------------------------------------------------------------------------------
resource "aws_lb_target_group" "api_http" {
  count = var.enable_http_listener ? 1 : 0

  name_prefix = "dpht-"
  port        = 8080
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = "/actuator/health/readiness"
    port                = "8080"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
  }

  deregistration_delay = 30

  tags = {
    Name = "${var.project_name}-${var.environment}-tg-http"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_target_group_attachment" "api_http" {
  count = var.enable_http_listener ? 1 : 0

  target_group_arn = aws_lb_target_group.api_http[0].arn
  target_id        = var.ec2_instance_id
  port             = 8080
}

resource "aws_lb_listener" "api_http" {
  count = var.enable_http_listener ? 1 : 0

  load_balancer_arn = aws_lb.api.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api_http[0].arn
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-listener-http"
  }
}
