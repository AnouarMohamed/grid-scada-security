resource "aws_security_group" "endpoints" {
  name        = "${local.name}-endpoints"
  description = "TLS from private EKS workers to required AWS service endpoints"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${local.name}-endpoints"
  }
}

resource "aws_vpc_security_group_ingress_rule" "endpoint_https" {
  for_each = toset(var.cloud_subnet_cidrs)

  security_group_id = aws_security_group.endpoints.id
  description       = "HTTPS from EKS worker subnet ${each.value}"
  cidr_ipv4         = each.value
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}

resource "aws_vpc_endpoint" "interface" {
  for_each = local.interface_endpoint_services

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = var.cloud_subnet_ids
  security_group_ids  = [aws_security_group.endpoints.id]

  tags = {
    Name = "${local.name}-${replace(each.value, ".", "-")}"
  }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [var.cloud_route_table_id]

  tags = {
    Name = "${local.name}-s3"
  }
}

