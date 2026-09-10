resource "aws_secretsmanager_secret" "runtime" {
  for_each = var.enable_runtime ? local.stateful_services : toset([])

  name                    = "${local.name}/${each.value}"
  description             = "Runtime credentials for ${each.value}; value is populated out of band."
  recovery_window_in_days = 7
}

resource "aws_efs_file_system" "service" {
  for_each = var.enable_runtime ? local.stateful_services : toset([])

  encrypted        = true
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = {
    Name = "${local.name}-${each.value}"
  }
}

resource "aws_efs_backup_policy" "service" {
  for_each = aws_efs_file_system.service

  file_system_id = each.value.id

  backup_policy {
    status = "ENABLED"
  }
}

locals {
  efs_identity = {
    influxdb = { uid = 1000, gid = 1000 }
    grafana  = { uid = 472, gid = 472 }
  }
  efs_mount_targets = var.enable_runtime ? {
    for pair in setproduct(local.stateful_services, toset(keys(aws_subnet.cloud))) :
    "${pair[0]}-${pair[1]}" => {
      service = pair[0]
      az      = pair[1]
    }
  } : {}
}

resource "aws_efs_access_point" "service" {
  for_each = aws_efs_file_system.service

  file_system_id = each.value.id

  posix_user {
    uid = local.efs_identity[each.key].uid
    gid = local.efs_identity[each.key].gid
  }

  root_directory {
    path = "/${each.key}"

    creation_info {
      owner_uid   = local.efs_identity[each.key].uid
      owner_gid   = local.efs_identity[each.key].gid
      permissions = "0750"
    }
  }
}

resource "aws_efs_mount_target" "service" {
  for_each = local.efs_mount_targets

  file_system_id  = aws_efs_file_system.service[each.value.service].id
  subnet_id       = aws_subnet.cloud[each.value.az].id
  security_groups = [aws_security_group.efs.id]
}
