mock_provider "aws" {
  override_data {
    target = data.aws_availability_zones.available
    values = {
      names = ["us-east-1a", "us-east-1b"]
    }
  }

  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "123456789012"
      arn        = "arn:aws:iam::123456789012:user/terraform-test"
      user_id    = "AIDATEST"
    }
  }

  override_data {
    target = data.aws_partition.current
    values = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }

  override_data {
    target = data.aws_prefix_list.s3
    values = {
      id   = "pl-12345678"
      name = "com.amazonaws.us-east-1.s3"
    }
  }
}

mock_provider "tls" {}

variables {
  workload_role_permissions_boundary_arn = "arn:aws:iam::123456789012:policy/gridguard/gridguard-aws-sandbox-workload-boundary"
}

run "foundation_defaults_are_safe" {
  command = plan

  assert {
    condition     = output.runtime_enabled == false
    error_message = "Runtime resources must be disabled by default."
  }

  assert {
    condition     = output.estimated_billable_features.nat_gateways == 0
    error_message = "The NAT gateway must be disabled by default."
  }

  assert {
    condition     = length(output.ecr_repository_urls) == 4
    error_message = "The foundation must create all four ECR repositories."
  }

  assert {
    condition = alltrue([
      aws_iam_role.flow.permissions_boundary == var.workload_role_permissions_boundary_arn,
      aws_iam_role.ecs_execution.permissions_boundary == var.workload_role_permissions_boundary_arn,
    ])
    error_message = "Every foundation workload role must use the required permissions boundary."
  }
}

run "runtime_graph_expands_with_zero_tasks" {
  command = plan

  variables {
    enable_runtime       = true
    enable_vpc_endpoints = true
    desired_counts = {
      power_sim       = 0
      modbus_ingestor = 0
      influxdb        = 0
      grafana         = 0
    }
  }

  assert {
    condition     = output.runtime_enabled == true
    error_message = "The runtime graph should be enabled for this test."
  }

  assert {
    condition     = length(output.runtime_secret_arns) == 2
    error_message = "Runtime mode must create the InfluxDB and Grafana secret containers."
  }


  assert {
    condition = alltrue([
      for role in values(aws_iam_role.ecs_storage) :
      role.permissions_boundary == var.workload_role_permissions_boundary_arn
    ])
    error_message = "Every stateful ECS task role must use the required permissions boundary."
  }
}

run "github_role_accepts_existing_oidc_provider" {
  command = plan

  variables {
    enable_github_oidc_role = true
    github_oidc_provider_arn = (
      "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    )
  }

  assert {
    condition     = length(aws_iam_role.github_deploy) == 1
    error_message = "An existing GitHub OIDC provider must support deployment-role creation."
  }
}

run "runtime_requires_private_endpoints" {
  command = plan

  variables {
    enable_runtime       = true
    enable_vpc_endpoints = false
  }

  expect_failures = [terraform_data.invariants]
}

run "public_grafana_requires_tls_certificate" {
  command = plan

  variables {
    enable_runtime       = true
    enable_vpc_endpoints = true
    grafana_public       = true
  }

  expect_failures = [terraform_data.invariants]
}

run "deployment_policy_requires_github_role" {
  command = plan

  variables {
    github_deploy_policy_arn = "arn:aws:iam::123456789012:policy/gridguard-deploy"
  }

  expect_failures = [terraform_data.invariants]
}

run "public_internet_operator_cidr_is_rejected" {
  command = plan

  variables {
    operator_cidrs = ["0.0.0.0/0"]
  }

  expect_failures = [var.operator_cidrs]
}

run "mutable_latest_image_tags_are_rejected" {
  command = plan

  variables {
    image_tags = {
      power_sim       = "latest"
      modbus_ingestor = "0.1.0"
      influxdb        = "2.9.1"
      grafana         = "12.4.10"
    }
  }

  expect_failures = [var.image_tags]
}

run "public_vpc_space_is_rejected" {
  command = plan

  variables {
    vpc_cidr = "203.0.0.0/16"
  }

  expect_failures = [var.vpc_cidr]
}

run "cross_account_workload_boundary_is_rejected" {
  command = plan

  variables {
    workload_role_permissions_boundary_arn = "arn:aws:iam::999999999999:policy/gridguard/workload-boundary"
  }

  expect_failures = [terraform_data.invariants]
}

run "stateful_multi_writer_counts_are_rejected" {
  command = plan

  variables {
    desired_counts = {
      power_sim       = 1
      modbus_ingestor = 1
      influxdb        = 2
      grafana         = 1
    }
  }

  expect_failures = [var.desired_counts]
}
