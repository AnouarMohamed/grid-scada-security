# Shared Glossary

Enough vocabulary from each track for the other person to follow along,
without needing to become an expert in it.

## Power systems terms (for the DevSecOps person)

- **Power flow**: the calculation of voltage, current, and power at every
  point in a grid, given loads and generation. The core simulation output.
- **Bus**: a node in the grid (roughly: a connection point — a substation, a
  transformer, a load point).
- **DER (Distributed Energy Resource)**: small-scale generation like rooftop
  solar, connected at the distribution level rather than centrally.
- **State estimation**: the process a grid operator uses to reconcile noisy,
  redundant sensor readings into a trusted picture of grid state.
- **Bad-data detection**: the traditional defense that flags sensor readings
  inconsistent with the rest of the system.
- **False Data Injection Attack (FDIA)**: a falsified set of sensor readings
  crafted to be internally consistent enough to evade bad-data detection.

## DevSecOps/cloud terms (for the Power Systems person)

- **IaC (Infrastructure as Code)**: infrastructure defined in text files
  (e.g., Terraform) instead of manually clicked together, so it's
  reproducible.
- **Container**: a packaged, isolated way to run software (Docker); the
  telemetry server and pipeline services will likely run in these.
- **VPC / network segmentation**: splitting a cloud network into isolated
  zones — used here to mimic the real-world separation between operational
  technology (OT) and IT networks.
- **IDS (Intrusion Detection System)**: software watching network traffic for
  attack patterns (e.g., Suricata, Zeek).
- **SIEM**: a system that aggregates security events/alerts into one place
  (e.g., Wazuh, ELK) — where alerts about your attacks will surface.
- **CI/CD**: automated pipelines that build, test, and scan code on every
  change (e.g., GitHub Actions).

## Protocol terms (both tracks need these)

- **Modbus TCP**: a simple industrial protocol for reading/writing "registers"
  (numeric values) over a network — the easiest telemetry format to start
  with.
- **DNP3**: a more complex industrial protocol, the real standard used by
  North American utility SCADA systems — a stretch goal beyond Modbus.
