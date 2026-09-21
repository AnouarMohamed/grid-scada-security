resource "aws_ecs_cluster" "this" {
  name = local.name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }
}

resource "aws_cloudwatch_log_group" "service" {
  for_each = local.service_names

  name              = "/gridguard/${var.environment}/${each.value}"
  retention_in_days = var.log_retention_days
}

resource "aws_service_discovery_private_dns_namespace" "this" {
  count = var.enable_runtime ? 1 : 0

  name        = "gridguard.internal"
  description = "Private service discovery for the GridGuard sandbox"
  vpc         = aws_vpc.this.id
}

resource "aws_service_discovery_service" "service" {
  for_each = var.enable_runtime ? local.service_names : toset([])

  name = each.value

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.this[0].id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  # ECS manages custom health for private discovery; AWS fixes this value at 1.
  health_check_custom_config {
    failure_threshold = 1
  }
}

locals {
  image_uris = {
    power_sim       = "${aws_ecr_repository.service["power-sim"].repository_url}@${var.image_digests.power_sim}"
    modbus_ingestor = "${aws_ecr_repository.service["modbus-ingestor"].repository_url}@${var.image_digests.modbus_ingestor}"
    influxdb        = "${aws_ecr_repository.service["influxdb"].repository_url}@${var.image_digests.influxdb}"
    grafana         = "${aws_ecr_repository.service["grafana"].repository_url}@${var.image_digests.grafana}"
  }

  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-region        = var.aws_region
      awslogs-stream-prefix = "ecs"
    }
  }
}

resource "aws_ecs_task_definition" "power_sim" {
  count = var.enable_runtime ? 1 : 0

  family                   = "${local.name}-power-sim"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_execution.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name                   = "power-sim"
      image                  = local.image_uris.power_sim
      essential              = true
      readonlyRootFilesystem = true
      command                = ["serve"]
      portMappings = [
        {
          name          = "modbus"
          containerPort = local.modbus_port
          hostPort      = local.modbus_port
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "GRIDGUARD_MODBUS_HOST", value = "0.0.0.0" },
        { name = "GRIDGUARD_MODBUS_PORT", value = tostring(local.modbus_port) },
        { name = "GRIDGUARD_MODBUS_UNIT_ID", value = "1" },
        { name = "GRIDGUARD_SIM_INTERVAL_SECONDS", value = "2" },
        { name = "GRIDGUARD_SCENARIO", value = "baseline-modbus" },
      ]
      linuxParameters = {
        initProcessEnabled = true
        tmpfs = [
          {
            containerPath = "/tmp"
            size          = 16
            mountOptions  = ["rw", "nosuid", "nodev", "noexec"]
          }
        ]
      }
      healthCheck = {
        command     = ["CMD-SHELL", "python -m power_sim healthcheck"]
        interval    = 15
        timeout     = 5
        retries     = 3
        startPeriod = 30
      }
      logConfiguration = merge(local.log_configuration, {
        options = merge(local.log_configuration.options, {
          awslogs-group = aws_cloudwatch_log_group.service["power-sim"].name
        })
      })
    }
  ])

  depends_on = [terraform_data.invariants]
}

resource "aws_ecs_task_definition" "influxdb" {
  count = var.enable_runtime ? 1 : 0

  family                   = "${local.name}-influxdb"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "1024"
  memory                   = "2048"
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_storage["influxdb"].arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  volume {
    name = "influxdb-data"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.service["influxdb"].id
      transit_encryption = "ENABLED"

      authorization_config {
        access_point_id = aws_efs_access_point.service["influxdb"].id
        iam             = "ENABLED"
      }
    }
  }

  container_definitions = jsonencode([
    {
      name      = "influxdb"
      image     = local.image_uris.influxdb
      essential = true
      portMappings = [
        {
          name          = "influxdb"
          containerPort = 8086
          hostPort      = 8086
          protocol      = "tcp"
          appProtocol   = "http"
        }
      ]
      environment = [
        { name = "DOCKER_INFLUXDB_INIT_MODE", value = "setup" },
        { name = "DOCKER_INFLUXDB_INIT_ORG", value = "gridguard" },
        { name = "DOCKER_INFLUXDB_INIT_BUCKET", value = "gridguard_telemetry" },
        { name = "DOCKER_INFLUXDB_INIT_RETENTION", value = "168h" },
      ]
      secrets = [
        {
          name      = "DOCKER_INFLUXDB_INIT_USERNAME"
          valueFrom = "${aws_secretsmanager_secret.runtime["influxdb"].arn}:username::"
        },
        {
          name      = "DOCKER_INFLUXDB_INIT_PASSWORD"
          valueFrom = "${aws_secretsmanager_secret.runtime["influxdb"].arn}:password::"
        },
        {
          name      = "DOCKER_INFLUXDB_INIT_ADMIN_TOKEN"
          valueFrom = "${aws_secretsmanager_secret.runtime["influxdb"].arn}:token::"
        },
      ]
      mountPoints = [
        {
          sourceVolume  = "influxdb-data"
          containerPath = "/var/lib/influxdb2"
          readOnly      = false
        }
      ]
      healthCheck = {
        command     = ["CMD-SHELL", "influx ping --host http://127.0.0.1:8086"]
        interval    = 15
        timeout     = 5
        retries     = 5
        startPeriod = 60
      }
      logConfiguration = merge(local.log_configuration, {
        options = merge(local.log_configuration.options, {
          awslogs-group = aws_cloudwatch_log_group.service["influxdb"].name
        })
      })
    }
  ])

  depends_on = [aws_iam_role_policy.ecs_secrets, aws_iam_role_policy.ecs_efs]
}

resource "aws_ecs_task_definition" "modbus_ingestor" {
  count = var.enable_runtime ? 1 : 0

  family                   = "${local.name}-modbus-ingestor"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name                   = "modbus-ingestor"
      image                  = local.image_uris.modbus_ingestor
      essential              = true
      readonlyRootFilesystem = true
      command                = ["ingest"]
      environment = [
        { name = "GRIDGUARD_MODBUS_MODE", value = "tcp" },
        { name = "GRIDGUARD_MODBUS_SOURCE_ID", value = "modbus_tcp" },
        { name = "GRIDGUARD_MODBUS_HOST", value = "power-sim.gridguard.internal" },
        { name = "GRIDGUARD_MODBUS_PORT", value = tostring(local.modbus_port) },
        { name = "GRIDGUARD_MODBUS_UNIT_ID", value = "1" },
        { name = "GRIDGUARD_SCENARIO", value = "baseline-modbus" },
        { name = "GRIDGUARD_ATTACK_FLAG", value = "0" },
        { name = "GRIDGUARD_INFLUX_URL", value = "http://influxdb.gridguard.internal:8086" },
        { name = "GRIDGUARD_INFLUX_ORG", value = "gridguard" },
        { name = "GRIDGUARD_INFLUX_BUCKET", value = "gridguard_telemetry" },
        { name = "GRIDGUARD_MODBUS_STATUS_FILE", value = "/tmp/gridguard-modbus-ingestor-ready" },
      ]
      secrets = [
        {
          name      = "GRIDGUARD_INFLUX_TOKEN"
          valueFrom = "${aws_secretsmanager_secret.runtime["influxdb"].arn}:token::"
        },
      ]
      linuxParameters = {
        initProcessEnabled = true
        tmpfs = [
          {
            containerPath = "/tmp"
            size          = 16
            mountOptions  = ["rw", "nosuid", "nodev", "noexec"]
          }
        ]
      }
      healthCheck = {
        command     = ["CMD-SHELL", "python -m gridguard_modbus_ingestor healthcheck"]
        interval    = 15
        timeout     = 5
        retries     = 5
        startPeriod = 45
      }
      logConfiguration = merge(local.log_configuration, {
        options = merge(local.log_configuration.options, {
          awslogs-group = aws_cloudwatch_log_group.service["modbus-ingestor"].name
        })
      })
    }
  ])

  depends_on = [aws_iam_role_policy.ecs_secrets]
}

resource "aws_ecs_task_definition" "grafana" {
  count = var.enable_runtime ? 1 : 0

  family                   = "${local.name}-grafana"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_storage["grafana"].arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  volume {
    name = "grafana-data"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.service["grafana"].id
      transit_encryption = "ENABLED"

      authorization_config {
        access_point_id = aws_efs_access_point.service["grafana"].id
        iam             = "ENABLED"
      }
    }
  }

  container_definitions = jsonencode([
    {
      name      = "grafana"
      image     = local.image_uris.grafana
      essential = true
      portMappings = [
        {
          name          = "grafana"
          containerPort = 3000
          hostPort      = 3000
          protocol      = "tcp"
          appProtocol   = "http"
        }
      ]
      environment = [
        { name = "GF_USERS_ALLOW_SIGN_UP", value = "false" },
        { name = "GF_AUTH_ANONYMOUS_ENABLED", value = "false" },
        { name = "GF_ANALYTICS_REPORTING_ENABLED", value = "false" },
        { name = "GF_ANALYTICS_CHECK_FOR_UPDATES", value = "false" },
        { name = "GF_ANALYTICS_CHECK_FOR_PLUGIN_UPDATES", value = "false" },
        { name = "GF_PLUGINS_PREINSTALL_DISABLED", value = "true" },
        { name = "INFLUXDB_URL", value = "http://influxdb.gridguard.internal:8086" },
        { name = "INFLUXDB_ORG", value = "gridguard" },
        { name = "INFLUXDB_BUCKET", value = "gridguard_telemetry" },
      ]
      secrets = [
        {
          name      = "GF_SECURITY_ADMIN_USER"
          valueFrom = "${aws_secretsmanager_secret.runtime["grafana"].arn}:username::"
        },
        {
          name      = "GF_SECURITY_ADMIN_PASSWORD"
          valueFrom = "${aws_secretsmanager_secret.runtime["grafana"].arn}:password::"
        },
        {
          name      = "INFLUXDB_ADMIN_TOKEN"
          valueFrom = "${aws_secretsmanager_secret.runtime["influxdb"].arn}:token::"
        },
      ]
      mountPoints = [
        {
          sourceVolume  = "grafana-data"
          containerPath = "/var/lib/grafana"
          readOnly      = false
        }
      ]
      healthCheck = {
        command     = ["CMD-SHELL", "wget -q -O - http://127.0.0.1:3000/api/health >/dev/null"]
        interval    = 15
        timeout     = 5
        retries     = 5
        startPeriod = 60
      }
      logConfiguration = merge(local.log_configuration, {
        options = merge(local.log_configuration.options, {
          awslogs-group = aws_cloudwatch_log_group.service["grafana"].name
        })
      })
    }
  ])

  depends_on = [aws_iam_role_policy.ecs_secrets, aws_iam_role_policy.ecs_efs]
}

resource "aws_ecs_service" "power_sim" {
  count = var.enable_runtime ? 1 : 0

  name             = "power-sim"
  cluster          = aws_ecs_cluster.this.id
  task_definition  = aws_ecs_task_definition.power_sim[0].arn
  desired_count    = var.desired_counts.power_sim
  launch_type      = "FARGATE"
  platform_version = "1.4.0"

  enable_ecs_managed_tags = true
  propagate_tags          = "SERVICE"

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    assign_public_ip = false
    subnets          = values(aws_subnet.ot)[*].id
    security_groups  = [aws_security_group.power_sim.id]
  }

  service_registries {
    registry_arn   = aws_service_discovery_service.service["power-sim"].arn
    container_name = "power-sim"
  }

  depends_on = [aws_vpc_endpoint.interface, aws_vpc_endpoint.s3]
}

resource "aws_ecs_service" "influxdb" {
  count = var.enable_runtime ? 1 : 0

  name             = "influxdb"
  cluster          = aws_ecs_cluster.this.id
  task_definition  = aws_ecs_task_definition.influxdb[0].arn
  desired_count    = var.desired_counts.influxdb
  launch_type      = "FARGATE"
  platform_version = "1.4.0"

  enable_ecs_managed_tags = true
  propagate_tags          = "SERVICE"

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    assign_public_ip = false
    subnets          = values(aws_subnet.cloud)[*].id
    security_groups  = [aws_security_group.influxdb.id]
  }

  service_registries {
    registry_arn   = aws_service_discovery_service.service["influxdb"].arn
    container_name = "influxdb"
  }

  depends_on = [aws_efs_mount_target.service, aws_vpc_endpoint.interface, aws_vpc_endpoint.s3]
}

resource "aws_ecs_service" "modbus_ingestor" {
  count = var.enable_runtime ? 1 : 0

  name             = "modbus-ingestor"
  cluster          = aws_ecs_cluster.this.id
  task_definition  = aws_ecs_task_definition.modbus_ingestor[0].arn
  desired_count    = var.desired_counts.modbus_ingestor
  launch_type      = "FARGATE"
  platform_version = "1.4.0"

  enable_ecs_managed_tags = true
  propagate_tags          = "SERVICE"

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    assign_public_ip = false
    subnets          = values(aws_subnet.cloud)[*].id
    security_groups  = [aws_security_group.modbus_ingestor.id]
  }

  service_registries {
    registry_arn   = aws_service_discovery_service.service["modbus-ingestor"].arn
    container_name = "modbus-ingestor"
  }

  depends_on = [aws_ecs_service.power_sim, aws_ecs_service.influxdb]
}

resource "aws_ecs_service" "grafana" {
  count = var.enable_runtime ? 1 : 0

  name             = "grafana"
  cluster          = aws_ecs_cluster.this.id
  task_definition  = aws_ecs_task_definition.grafana[0].arn
  desired_count    = var.desired_counts.grafana
  launch_type      = "FARGATE"
  platform_version = "1.4.0"

  enable_ecs_managed_tags = true
  propagate_tags          = "SERVICE"

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  health_check_grace_period_seconds = 60

  network_configuration {
    assign_public_ip = false
    subnets          = values(aws_subnet.cloud)[*].id
    security_groups  = [aws_security_group.grafana.id]
  }

  service_registries {
    registry_arn   = aws_service_discovery_service.service["grafana"].arn
    container_name = "grafana"
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.grafana[0].arn
    container_name   = "grafana"
    container_port   = 3000
  }

  depends_on = [aws_efs_mount_target.service, aws_lb_listener.grafana]
}
