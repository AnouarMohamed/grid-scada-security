resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = local.name
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${local.name}-igw"
  }
}

resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.key
  cidr_block              = each.value
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name}-public-${each.key}"
    Zone = "public-ingress"
  }
}

resource "aws_subnet" "cloud" {
  for_each = local.cloud_subnets

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.key
  cidr_block              = each.value
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name}-cloud-${each.key}"
    Zone = "cloud-core"
  }
}

resource "aws_subnet" "ot" {
  for_each = local.ot_subnets

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.key
  cidr_block              = each.value
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name}-ot-${each.key}"
    Zone = "ot-sim"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${local.name}-public"
  }
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  count = var.enable_nat_gateway ? 1 : 0

  domain = "vpc"

  tags = {
    Name = "${local.name}-nat"
  }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  count = var.enable_nat_gateway ? 1 : 0

  allocation_id = aws_eip.nat[0].id
  subnet_id     = values(aws_subnet.public)[0].id

  tags = {
    Name = "${local.name}-nat"
  }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "cloud" {
  vpc_id = aws_vpc.this.id

  dynamic "route" {
    for_each = var.enable_nat_gateway ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.this[0].id
    }
  }

  tags = {
    Name = "${local.name}-cloud"
  }
}

resource "aws_route_table_association" "cloud" {
  for_each = aws_subnet.cloud

  subnet_id      = each.value.id
  route_table_id = aws_route_table.cloud.id
}

resource "aws_route_table" "ot" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${local.name}-ot-isolated"
  }
}

resource "aws_route_table_association" "ot" {
  for_each = aws_subnet.ot

  subnet_id      = each.value.id
  route_table_id = aws_route_table.ot.id
}

resource "aws_cloudwatch_log_group" "flow" {
  name              = "/gridguard/${var.environment}/vpc-flow"
  retention_in_days = var.log_retention_days
}

resource "aws_iam_role" "flow" {
  name                 = "${local.name}-vpc-flow-logs"
  permissions_boundary = var.workload_role_permissions_boundary_arn
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "flow" {
  name = "${local.name}-vpc-flow-logs"
  role = aws_iam_role.flow.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WriteFlowLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "${aws_cloudwatch_log_group.flow.arn}:*"
      },
      {
        Sid    = "DescribeFlowLogDestinations"
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_flow_log" "this" {
  iam_role_arn    = aws_iam_role.flow.arn
  log_destination = aws_cloudwatch_log_group.flow.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.this.id

  depends_on = [aws_iam_role_policy.flow]
}
