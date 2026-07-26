module "network_boundary" {
  source = "../../modules/network-boundary"

  project_name = var.project_name
  environment  = var.environment

  zones = {
    ot-sim = {
      cidr            = "10.40.10.0/24"
      description     = "Synthetic operational-technology segment for fake grid telemetry."
      exposure        = "internal"
      allowed_ingress = []
      allowed_egress  = ["telemetry-ingestor"]
    }

    cloud-core = {
      cidr            = "10.40.20.0/24"
      description     = "Telemetry platform segment for InfluxDB, Grafana, and ingestion."
      exposure        = "host-loopback"
      allowed_ingress = ["telemetry-ingestor", "operator-workstation"]
      allowed_egress  = []
    }
  }

  boundary_services = {
    telemetry-ingestor = {
      description        = "Temporary fake-data ingestor; later replaced by Modbus/DNP3 ingestion."
      connects           = ["ot-sim", "cloud-core"]
      future_replacement = "real-modbus-ingestion-service"
    }

    modbus-ingestor-fixture = {
      description        = "DevSecOps-owned Modbus register-map fixture ingestor."
      connects           = ["ot-sim", "cloud-core"]
      future_replacement = "real-modbus-ingestion-service"
    }
  }
}

module "observability_foundation" {
  source = "../../modules/observability-foundation"

  project_name = var.project_name
  environment  = var.environment

  services = {
    influxdb = {
      zone        = "cloud-core"
      protocol    = "http"
      port        = 8086
      public      = false
      health_path = "/health"
      description = "Time-series database for fake and future SCADA telemetry."
    }

    grafana = {
      zone        = "cloud-core"
      protocol    = "http"
      port        = 3000
      public      = false
      health_path = "/api/health"
      description = "Dashboard surface for telemetry and later detection views."
    }

    fake-grid-source = {
      zone        = "ot-sim"
      protocol    = "http"
      port        = 8080
      public      = false
      health_path = "/healthz"
      description = "Synthetic OT-side telemetry source used before the Modbus emulator exists."
    }

    modbus-ingestor-fixture = {
      zone        = "cloud-core"
      protocol    = "tcp"
      port        = 502
      public      = false
      health_path = ""
      description = "Fixture-backed Modbus register-map ingestor for receiver-side contract tests."
    }
  }
}
