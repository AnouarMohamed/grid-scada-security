resource "aws_security_group" "endpoints" {
  name        = "${local.name}-endpoints"
  description = "TLS access to private AWS service endpoints"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${local.name}-endpoints"
  }
}

resource "aws_security_group" "power_sim" {
  name        = "${local.name}-power-sim"
  description = "OT-side power simulator"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${local.name}-power-sim"
    Zone = "ot-sim"
  }
}

resource "aws_security_group" "modbus_ingestor" {
  name        = "${local.name}-modbus-ingestor"
  description = "Only service allowed to cross the modeled OT/cloud boundary"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${local.name}-modbus-ingestor"
    Zone = "boundary"
  }
}

resource "aws_security_group" "influxdb" {
  name        = "${local.name}-influxdb"
  description = "Private InfluxDB telemetry store"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${local.name}-influxdb"
    Zone = "cloud-core"
  }
}

resource "aws_security_group" "grafana" {
  name        = "${local.name}-grafana"
  description = "Private Grafana tasks"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${local.name}-grafana"
    Zone = "cloud-core"
  }
}

resource "aws_security_group" "alb" {
  name        = "${local.name}-grafana-alb"
  description = "Operator ingress to the Grafana load balancer"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${local.name}-grafana-alb"
  }
}

resource "aws_security_group" "efs" {
  name        = "${local.name}-efs"
  description = "NFS access from stateful telemetry services"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${local.name}-efs"
  }
}

resource "aws_vpc_security_group_ingress_rule" "endpoint_https" {
  for_each = local.task_security_groups

  security_group_id            = aws_security_group.endpoints.id
  description                  = "TLS from the ${replace(each.key, "_", "-")} tasks"
  referenced_security_group_id = each.value
  from_port                    = 443
  ip_protocol                  = "tcp"
  to_port                      = 443
}

resource "aws_vpc_security_group_ingress_rule" "power_modbus" {
  security_group_id            = aws_security_group.power_sim.id
  description                  = "Modbus TCP from the boundary ingestor"
  referenced_security_group_id = aws_security_group.modbus_ingestor.id
  from_port                    = local.modbus_port
  ip_protocol                  = "tcp"
  to_port                      = local.modbus_port
}

resource "aws_vpc_security_group_egress_rule" "ingestor_modbus" {
  security_group_id            = aws_security_group.modbus_ingestor.id
  description                  = "Poll the OT-side Modbus simulator"
  referenced_security_group_id = aws_security_group.power_sim.id
  from_port                    = local.modbus_port
  ip_protocol                  = "tcp"
  to_port                      = local.modbus_port
}

resource "aws_vpc_security_group_ingress_rule" "influx_ingestor" {
  security_group_id            = aws_security_group.influxdb.id
  description                  = "Telemetry writes from the boundary ingestor"
  referenced_security_group_id = aws_security_group.modbus_ingestor.id
  from_port                    = 8086
  ip_protocol                  = "tcp"
  to_port                      = 8086
}

resource "aws_vpc_security_group_ingress_rule" "influx_grafana" {
  security_group_id            = aws_security_group.influxdb.id
  description                  = "Telemetry queries from Grafana"
  referenced_security_group_id = aws_security_group.grafana.id
  from_port                    = 8086
  ip_protocol                  = "tcp"
  to_port                      = 8086
}

resource "aws_vpc_security_group_egress_rule" "ingestor_influx" {
  security_group_id            = aws_security_group.modbus_ingestor.id
  description                  = "Write telemetry and detections to InfluxDB"
  referenced_security_group_id = aws_security_group.influxdb.id
  from_port                    = 8086
  ip_protocol                  = "tcp"
  to_port                      = 8086
}

resource "aws_vpc_security_group_egress_rule" "grafana_influx" {
  security_group_id            = aws_security_group.grafana.id
  description                  = "Query InfluxDB"
  referenced_security_group_id = aws_security_group.influxdb.id
  from_port                    = 8086
  ip_protocol                  = "tcp"
  to_port                      = 8086
}

resource "aws_vpc_security_group_ingress_rule" "grafana_alb" {
  security_group_id            = aws_security_group.grafana.id
  description                  = "Dashboard traffic from the load balancer"
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 3000
  ip_protocol                  = "tcp"
  to_port                      = 3000
}

resource "aws_vpc_security_group_egress_rule" "alb_grafana" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Forward dashboard traffic to Grafana"
  referenced_security_group_id = aws_security_group.grafana.id
  from_port                    = 3000
  ip_protocol                  = "tcp"
  to_port                      = 3000
}

resource "aws_vpc_security_group_ingress_rule" "alb_operator" {
  for_each = toset(var.operator_cidrs)

  security_group_id = aws_security_group.alb.id
  description       = "Operator access from ${each.value}"
  cidr_ipv4         = each.value
  from_port         = local.grafana_listener_port
  ip_protocol       = "tcp"
  to_port           = local.grafana_listener_port
}

resource "aws_vpc_security_group_ingress_rule" "efs_influx" {
  security_group_id            = aws_security_group.efs.id
  description                  = "InfluxDB persistent storage"
  referenced_security_group_id = aws_security_group.influxdb.id
  from_port                    = 2049
  ip_protocol                  = "tcp"
  to_port                      = 2049
}

resource "aws_vpc_security_group_ingress_rule" "efs_grafana" {
  security_group_id            = aws_security_group.efs.id
  description                  = "Grafana persistent storage"
  referenced_security_group_id = aws_security_group.grafana.id
  from_port                    = 2049
  ip_protocol                  = "tcp"
  to_port                      = 2049
}

resource "aws_vpc_security_group_egress_rule" "influx_efs" {
  security_group_id            = aws_security_group.influxdb.id
  description                  = "Mount the InfluxDB EFS access point"
  referenced_security_group_id = aws_security_group.efs.id
  from_port                    = 2049
  ip_protocol                  = "tcp"
  to_port                      = 2049
}

resource "aws_vpc_security_group_egress_rule" "grafana_efs" {
  security_group_id            = aws_security_group.grafana.id
  description                  = "Mount the Grafana EFS access point"
  referenced_security_group_id = aws_security_group.efs.id
  from_port                    = 2049
  ip_protocol                  = "tcp"
  to_port                      = 2049
}

locals {
  task_security_groups = {
    power_sim       = aws_security_group.power_sim.id
    modbus_ingestor = aws_security_group.modbus_ingestor.id
    influxdb        = aws_security_group.influxdb.id
    grafana         = aws_security_group.grafana.id
  }
  cloud_task_security_groups = {
    modbus_ingestor = aws_security_group.modbus_ingestor.id
    influxdb        = aws_security_group.influxdb.id
    grafana         = aws_security_group.grafana.id
  }
}

resource "aws_vpc_security_group_egress_rule" "task_endpoints" {
  for_each = local.task_security_groups

  security_group_id            = each.value
  description                  = "TLS to private AWS service endpoints"
  referenced_security_group_id = aws_security_group.endpoints.id
  from_port                    = 443
  ip_protocol                  = "tcp"
  to_port                      = 443
}

resource "aws_vpc_security_group_egress_rule" "task_s3" {
  for_each = local.task_security_groups

  security_group_id = each.value
  description       = "Pull ECR image layers from the regional S3 endpoint"
  prefix_list_id    = data.aws_prefix_list.s3.id
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "cloud_nat_https" {
  for_each = var.enable_nat_gateway ? local.cloud_task_security_groups : {}

  security_group_id = each.value
  description       = "Optional HTTPS egress through the cloud NAT gateway"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}
