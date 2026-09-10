resource "aws_lb" "grafana" {
  count = var.enable_runtime ? 1 : 0

  name                       = substr("${local.name}-grafana", 0, 32)
  internal                   = !var.grafana_public
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb.id]
  subnets                    = var.grafana_public ? values(aws_subnet.public)[*].id : values(aws_subnet.cloud)[*].id
  drop_invalid_header_fields = true
  enable_deletion_protection = false
}

resource "aws_lb_target_group" "grafana" {
  count = var.enable_runtime ? 1 : 0

  name        = substr("${local.name}-grafana", 0, 32)
  port        = 3000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.this.id

  deregistration_delay = 30

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    path                = "/api/health"
    matcher             = "200"
  }
}

resource "aws_lb_listener" "grafana" {
  count = var.enable_runtime ? 1 : 0

  load_balancer_arn = aws_lb.grafana[0].arn
  port              = local.grafana_listener_port
  protocol          = local.grafana_listener_protocol
  certificate_arn   = var.grafana_public ? var.grafana_certificate_arn : null
  ssl_policy        = var.grafana_public ? "ELBSecurityPolicy-TLS13-1-2-2021-06" : null

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana[0].arn
  }

  depends_on = [terraform_data.invariants]
}
