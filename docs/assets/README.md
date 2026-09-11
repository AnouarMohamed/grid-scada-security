# Architecture Diagram Assets

This directory contains the canonical GridGuard documentation diagrams and the
source icon files embedded into them.

## Diagram Set

| Asset | Purpose | Detail |
| --- | --- | --- |
| `gridguard-architecture.svg` | System overview and trust boundary | Mixed audience |
| `gridguard-aws-deployment.svg` | AWS runtime placement and network topology | Engineer |
| `gridguard-detection-flow.svg` | Scenario-to-alert data flow and recorded outcomes | Engineer |

All three diagrams are self-contained SVG files. Each logo is embedded as a
data URI so it renders in GitHub, browsers, PDF pipelines, and offline viewers.
The readable source copies under `icons/` exist for provenance and future
updates.

## Design System

The layout follows the editorial principles in
[Cathryn Lavery's Diagram Design](https://github.com/cathrynlavery/diagram-design)
at commit `8d8b2993ee2256ee7dfc0eeb3b5713aba3b60792`:

- one clear reading direction and a target density near 4/10;
- trust zones before connectors, connectors before nodes;
- orthogonal connectors with masked labels;
- no shadows, ornamental gradients, or generic card grids;
- at most two focal elements per diagram;
- technical values in monospace and human labels in sans-serif;
- an accessible `title`, `desc`, `role`, and `aria-labelledby` contract.

The GridGuard skin uses near-white paper, dark green-black ink, blue telemetry,
green detections, red attack or blocked paths, and amber for disabled or
operator-gated state. Color never carries meaning alone; labels, dash patterns,
and stop bars provide the same information.

## Fidelity Ledger

The diagrams deliberately do not put every resource into one canvas.

**System overview**

- Merged telemetry decoding and both local detectors into the Modbus ingestor,
  where that code actually runs.
- Collapsed the nine Modbus registers into the named protocol handoff.
- Collapsed CI jobs into one required gate.
- Omitted fixture-only fake telemetry services and future components.

**AWS deployment**

- Collapsed six subnets into three real tiers, each marked `x2` for the two
  availability zones.
- Collapsed four interface endpoints plus the S3 gateway endpoint into one
  named endpoint node.
- Collapsed individual security groups, IAM policies, EFS access points, mount
  targets, log groups, and route-table associations into their enforcement
  outcomes.
- Kept all four ECS services, both stateful stores, both load-balancer modes,
  the optional NAT path, service discovery, image registry, secrets, and logs.

**Detection flow**

- Collapsed nine registers into the five emitted signal families.
- Kept every executed scenario and both implemented detector families.
- Kept the observed outcome that exposes the current threshold-detector gap.

Not shown as implemented: DNP3, MQTT or another queue, mTLS, Suricata, Zeek,
Wazuh, ELK, or a topology/state-estimator detector. Those remain future work.

## Icon Provenance

| Icons | Source | Snapshot | Notes |
| --- | --- | --- | --- |
| AWS services and VPC | [AWS Architecture Icons](https://aws.amazon.com/architecture/icons/) | Q3 package `Icon-package_07312026`, downloaded 2026-09-11 | AWS-approved assets supplied for architecture diagrams |
| GitHub Invertocat | [GitHub Brand Toolkit](https://brand.github.com/foundations/logo) | Official logo package dated 2026-01-09 | Black high-contrast mark, used to identify GitHub integration |
| Grafana | [grafana/grafana](https://github.com/grafana/grafana/blob/a2b62a5683c92ae4c4a3ce36923c4a109293abff/public/img/grafana_icon.svg) | `a2b62a5683c92ae4c4a3ce36923c4a109293abff` | Upstream project asset |
| Terraform | [hashicorp/vscode-terraform](https://github.com/hashicorp/vscode-terraform/blob/c15fbbf94518dc969bfd3c1a998e363da66cbcf3/assets/icons/terraform_feature.svg) | `c15fbbf94518dc969bfd3c1a998e363da66cbcf3` | Upstream HashiCorp asset |
| InfluxDB | [Simple Icons](https://github.com/simple-icons/simple-icons/blob/5d5d4d1d28cbb00b21770bb69d8112da52211a95/icons/influxdb.svg) | `5d5d4d1d28cbb00b21770bb69d8112da52211a95` | CC0 vector of the InfluxDB brand mark |

Vendor names, marks, and service icons remain the property of their respective
owners. Their inclusion documents integrations and does not imply endorsement.

## Validation

Run the normal documentation gate:

```bash
make docs
```

For a visual release check, render the native diagrams plus README-width and
narrow-preview variants:

```bash
for name in gridguard-architecture gridguard-aws-deployment gridguard-detection-flow; do
  magick -background none "docs/assets/${name}.svg" "/tmp/${name}.png"
  magick "/tmp/${name}.png" -resize 720x "/tmp/${name}-720.png"
  magick "/tmp/${name}.png" -resize 458x "/tmp/${name}-458.png"
done
```

Inspect all three sizes. Acceptance requires centered content, loaded logos,
readable labels, no horizontal overflow or clipping, no connector-label
collisions, and no connector passing through a non-endpoint node. Diagram roots
and Markdown embeds must remain fluid-width so narrow documentation panes scale
the complete canvas instead of cropping it.

## Update Rule

Treat `compose.yaml`, the Python pipeline and detector code, the Modbus
register map, Grafana provisioning, and
`infra/terraform/environments/aws-sandbox` as the source of truth. Update a
diagram in the same change that modifies a represented boundary, protocol,
port, service, detector, resource flag, or verified outcome.
