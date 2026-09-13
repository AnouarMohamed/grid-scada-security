from pathlib import Path
from typing import Any

import yaml

WORKFLOW_PATH = Path(".github/workflows/image-evidence.yml")
EXPECTED_IMAGES = [
    {
        "component": "power-sim",
        "repository": "gridguard-aws-sandbox/power-sim",
        "digest": "sha256:f51d3dd888b3a2a2855bbba40725357a92d91c2a9bd6660fdd8a5a39505a9451",
    },
    {
        "component": "modbus-ingestor",
        "repository": "gridguard-aws-sandbox/modbus-ingestor",
        "digest": "sha256:18e13b46ed9fe4d89290ae8219b6cd897e3a8e3c6675f3069541779b49e2caa7",
    },
    {
        "component": "influxdb",
        "repository": "gridguard-aws-sandbox/influxdb",
        "digest": "sha256:66e4f468821b9a47f9eb0808d2e87c70d6ddd92c741450e9d78eff70ae856d67",
    },
    {
        "component": "grafana",
        "repository": "gridguard-aws-sandbox/grafana",
        "digest": "sha256:1fbc7b35e2e71e9ccf8178dc7b05369bc85a9000320ee40031743a868f566c5c",
    },
]
EXPECTED_ACTIONS = {
    "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1",
    "actions/attest@1e69f48acb82d1966a394da916b4c1698aa569d6",
    "actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a",
    "anchore/sbom-action@3ad7283483fc7af8ff2b4ea19663c2d5ca935e26",
    "aquasecurity/trivy-action@ed142fd0673e97e23eac54620cfb913e5ce36c25",
    "aws-actions/amazon-ecr-login@03f1aad4c6c7ffd436567f42f9384779290529bd",
    "aws-actions/configure-aws-credentials@cbe3b392738ccf3f987d68400dafcf4b0624a56c",
}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"{WORKFLOW_PATH}: {message}")


workflow: dict[Any, Any] = yaml.safe_load(WORKFLOW_PATH.read_text(encoding="utf-8"))
triggers = workflow.get("on", workflow.get(True))
require(triggers == {"workflow_dispatch": None}, "workflow must be manual-only")
require(
    workflow.get("permissions")
    == {"contents": "read", "id-token": "write", "attestations": "write"},
    "top-level permissions changed unexpectedly",
)

jobs = workflow.get("jobs", {})
require(set(jobs) == {"evidence"}, "workflow must contain only the evidence job")
job = jobs["evidence"]
require(job.get("environment") == "sandbox", "job must use the sandbox environment")
require(
    job.get("strategy", {}).get("fail-fast") is False,
    "all image evidence jobs must finish independently",
)
actual_images = job.get("strategy", {}).get("matrix", {}).get("include")
require(actual_images == EXPECTED_IMAGES, "release image matrix or runnable digest changed")
require(
    job.get("env", {}).get("AWS_ACCOUNT_ID") == "227755136916",
    "AWS account boundary changed unexpectedly",
)

steps = job.get("steps", [])
uses = {step["uses"] for step in steps if "uses" in step}
require(uses == EXPECTED_ACTIONS, "action set or immutable action revision changed")

by_uses = {step["uses"].split("@")[0]: step for step in steps if "uses" in step}
credentials = by_uses["aws-actions/configure-aws-credentials"].get("with", {})
require(
    credentials.get("allowed-account-ids") == "227755136916",
    "credential action must enforce the exact AWS account",
)
require(
    credentials.get("mask-aws-account-id") is True,
    "credential action must mask the AWS account ID",
)

sbom = by_uses["anchore/sbom-action"].get("with", {})
require(sbom.get("format") == "spdx-json", "SBOM must use SPDX JSON")
require(sbom.get("syft-version") == "v1.51.1", "unexpected Syft version")
require(sbom.get("upload-artifact") is False, "SBOM action must not upload separately")

trivy = by_uses["aquasecurity/trivy-action"].get("with", {})
require(trivy.get("version") == "v0.74.0", "unexpected Trivy version")
require(trivy.get("severity") == "HIGH,CRITICAL", "scan severity changed")
require(trivy.get("ignore-unfixed") is False, "unfixed findings must remain visible")
require(trivy.get("exit-code") == "0", "the explicit critical gate owns scan failure")

attestation = by_uses["actions/attest"].get("with", {})
require("sbom-path" in attestation, "attestation must carry the SPDX SBOM")
require(
    attestation.get("push-to-registry") in (None, False),
    "read-only workflow must not push attestations to ECR",
)

shell = "\n".join(str(step.get("run", "")) for step in steps).lower()
for forbidden in ("docker push", "ecr put-image", "ecr batch-delete-image"):
    require(forbidden not in shell, f"forbidden mutation command found: {forbidden}")
require("docker logout" in shell, "workflow must remove the ECR registry credential")
require("aws_secret_access_key=" in shell, "workflow must clear temporary AWS credentials")
require(".repodigests" in shell, "workflow must verify the digest-qualified image reference")
require(
    "image inspect --platform" not in shell,
    "workflow must remain compatible with GitHub-hosted Docker",
)

print("Validated manual signed-SBOM workflow and four immutable runnable digests.")
