resource "aws_vpc_endpoint" "interface" {
  for_each = var.enable_vpc_endpoints ? local.endpoint_services : toset([])

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.aws_region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = values(aws_subnet.cloud)[*].id
  security_group_ids  = [aws_security_group.endpoints.id]

  tags = {
    Name = "${local.name}-${replace(each.value, ".", "-")}"
  }
}

resource "aws_vpc_endpoint" "s3" {
  count = var.enable_vpc_endpoints ? 1 : 0

  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.cloud.id, aws_route_table.ot.id]

  tags = {
    Name = "${local.name}-s3"
  }
}
