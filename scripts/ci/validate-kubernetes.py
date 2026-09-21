from __future__ import annotations

from pathlib import Path
from typing import Any

import yaml

ROOT = Path("infra/kubernetes")
BASE = ROOT / "base"
AWS_OVERLAY = ROOT / "overlays" / "aws" / "kustomization.yaml"
AWS_COREDNS_POLICY = ROOT / "overlays" / "aws" / "coredns-network-policy.yaml"
EXPECTED_NAMESPACES = {
    "gridguard-ot",
    "gridguard-ingestion",
    "gridguard-observability",
}
EXPECTED_DEPLOYMENTS = {
    ("gridguard-ot", "power-sim"),
    ("gridguard-ingestion", "modbus-ingestor"),
    ("gridguard-observability", "influxdb"),
    ("gridguard-observability", "grafana"),
}
EXPECTED_AWS_IMAGES = {
    "gridguard/power-sim",
    "gridguard/modbus-ingestor",
    "gridguard/influxdb",
    "gridguard/grafana",
}
EXPECTED_RUNTIME_IDS = {
    ("gridguard-ot", "power-sim"): 999,
    ("gridguard-ingestion", "modbus-ingestor"): 999,
    ("gridguard-observability", "influxdb"): 1000,
    ("gridguard-observability", "grafana"): 472,
}


def fail(message: str) -> None:
    raise SystemExit(f"Kubernetes validation failed: {message}")


def load_documents() -> list[dict[str, Any]]:
    documents: list[dict[str, Any]] = []
    for path in sorted(BASE.glob("*.yaml")):
        if path.name == "kustomization.yaml":
            continue
        loaded = yaml.safe_load_all(path.read_text(encoding="utf-8"))
        for index, document in enumerate(loaded, start=1):
            if not isinstance(document, dict):
                fail(f"{path}:{index} is not a Kubernetes object")
            documents.append(document)
    return documents


def named(documents: list[dict[str, Any]], kind: str) -> dict[tuple[str, str], dict[str, Any]]:
    result: dict[tuple[str, str], dict[str, Any]] = {}
    for document in documents:
        if document.get("kind") != kind:
            continue
        metadata = document.get("metadata", {})
        key = (metadata.get("namespace", ""), metadata.get("name", ""))
        if key in result:
            fail(f"duplicate {kind} {key}")
        result[key] = document
    return result


def validate_namespaces(documents: list[dict[str, Any]]) -> None:
    actual = {
        document.get("metadata", {}).get("name")
        for document in documents
        if document.get("kind") == "Namespace"
    }
    if actual != EXPECTED_NAMESPACES:
        fail(f"namespace set is {sorted(actual)}, expected {sorted(EXPECTED_NAMESPACES)}")


def validate_deployments(documents: list[dict[str, Any]]) -> None:
    deployments = named(documents, "Deployment")
    if set(deployments) != EXPECTED_DEPLOYMENTS:
        fail(
            f"deployment set is {sorted(deployments)}, "
            f"expected {sorted(EXPECTED_DEPLOYMENTS)}"
        )

    for identity, deployment in deployments.items():
        template = deployment["spec"]["template"]["spec"]
        if template.get("automountServiceAccountToken") is not False:
            fail(f"{identity} must disable service-account token mounting")
        if template.get("serviceAccountName") in (None, "", "default"):
            fail(f"{identity} must use a dedicated service account")

        pod_security = template.get("securityContext", {})
        if pod_security.get("runAsNonRoot") is not True:
            fail(f"{identity} must run as non-root")
        expected_runtime_id = EXPECTED_RUNTIME_IDS[identity]
        if pod_security.get("runAsUser") != expected_runtime_id:
            fail(f"{identity} must run as numeric UID {expected_runtime_id}")
        if pod_security.get("runAsGroup") != expected_runtime_id:
            fail(f"{identity} must run as numeric GID {expected_runtime_id}")
        if pod_security.get("seccompProfile", {}).get("type") != "RuntimeDefault":
            fail(f"{identity} must use the RuntimeDefault seccomp profile")

        containers = template.get("containers", [])
        if len(containers) != 1:
            fail(f"{identity} must contain exactly one application container")
        container = containers[0]
        security = container.get("securityContext", {})
        if security.get("allowPrivilegeEscalation") is not False:
            fail(f"{identity} must disable privilege escalation")
        if security.get("readOnlyRootFilesystem") is not True:
            fail(f"{identity} must use a read-only root filesystem")
        if security.get("privileged") is True:
            fail(f"{identity} cannot run privileged")
        if security.get("capabilities", {}).get("drop") != ["ALL"]:
            fail(f"{identity} must drop all Linux capabilities")
        if container.get("imagePullPolicy") != "IfNotPresent":
            fail(f"{identity} must declare imagePullPolicy IfNotPresent")
        if not container.get("readinessProbe") or not container.get("livenessProbe"):
            fail(f"{identity} must define readiness and liveness probes")
        resources = container.get("resources", {})
        if not resources.get("requests") or not resources.get("limits"):
            fail(f"{identity} must define resource requests and limits")


def validate_services(documents: list[dict[str, Any]]) -> None:
    services = named(documents, "Service")
    if len(services) != 3:
        fail(f"expected three internal services, found {len(services)}")
    for identity, service in services.items():
        if service.get("spec", {}).get("type") != "ClusterIP":
            fail(f"{identity} must remain ClusterIP-only")


def validate_network_policies(documents: list[dict[str, Any]]) -> None:
    policies = named(documents, "NetworkPolicy")
    for namespace in EXPECTED_NAMESPACES:
        policy = policies.get((namespace, "default-deny-all"))
        if policy is None:
            fail(f"{namespace} is missing default-deny-all")
        spec = policy.get("spec", {})
        if spec.get("podSelector") != {}:
            fail(f"{namespace}/default-deny-all must select every pod")
        if set(spec.get("policyTypes", [])) != {"Ingress", "Egress"}:
            fail(f"{namespace}/default-deny-all must deny ingress and egress")
        if "ingress" in spec or "egress" in spec:
            fail(f"{namespace}/default-deny-all cannot contain allow rules")

    expected = {
        ("gridguard-ot", "default-deny-all"),
        ("gridguard-ingestion", "default-deny-all"),
        ("gridguard-observability", "default-deny-all"),
        ("kube-system", "allow-cluster-dns"),
        ("gridguard-ot", "allow-ingestor-to-power-sim"),
        ("gridguard-ingestion", "allow-ingestor-egress"),
        ("gridguard-observability", "allow-approved-influxdb-clients"),
        ("gridguard-observability", "allow-grafana-egress"),
        ("gridguard-observability", "allow-grafana-operator"),
    }
    if set(policies) != expected:
        fail(
            f"network-policy set is {sorted(policies)}, expected {sorted(expected)}"
        )

    allowed_ports = {53, 1502, 3000, 8086}
    for identity, policy in policies.items():
        serialized = yaml.safe_dump(policy)
        if "ipBlock:" in serialized:
            fail(f"{identity} cannot use CIDR-wide pod access")
        rules = policy.get("spec", {}).get("ingress", []) + policy.get("spec", {}).get(
            "egress", []
        )
        for rule in rules:
            for port in rule.get("ports", []):
                if port.get("port") not in allowed_ports:
                    fail(f"{identity} allows unexpected port {port.get('port')}")


def validate_no_committed_secrets(documents: list[dict[str, Any]]) -> None:
    forbidden = [document for document in documents if document.get("kind") == "Secret"]
    if forbidden:
        fail("committed Secret objects are forbidden; create them out of band")


def validate_aws_overlay() -> None:
    overlay = yaml.safe_load(AWS_OVERLAY.read_text(encoding="utf-8"))
    if overlay.get("resources") != ["../../base", "coredns-network-policy.yaml"]:
        fail("AWS overlay must include only the base and reviewed CoreDNS policy")
    images = overlay.get("images", [])
    by_name = {image.get("name"): image for image in images}
    if set(by_name) != EXPECTED_AWS_IMAGES:
        fail("AWS overlay must replace exactly the four GridGuard images")

    for name, image in by_name.items():
        repository = image.get("newName", "")
        digest = image.get("digest", "")
        if not repository.startswith(
            "227755136916.dkr.ecr.us-east-1.amazonaws.com/gridguard-aws-sandbox/"
        ):
            fail(f"{name} must use the reviewed private ECR namespace")
        if not digest.startswith("sha256:") or len(digest) != 71:
            fail(f"{name} must use an exact sha256 image digest")
        if "newTag" in image:
            fail(f"{name} cannot use a mutable tag in the AWS overlay")


def validate_aws_coredns_policy() -> None:
    policy = yaml.safe_load(AWS_COREDNS_POLICY.read_text(encoding="utf-8"))
    if policy.get("kind") != "NetworkPolicy":
        fail("AWS CoreDNS policy must be a NetworkPolicy")
    if policy.get("metadata") != {
        "name": "allow-coredns-aws-runtime",
        "namespace": "kube-system",
    }:
        fail("AWS CoreDNS policy identity changed")

    spec = policy.get("spec", {})
    if spec.get("podSelector") != {"matchLabels": {"k8s-app": "kube-dns"}}:
        fail("AWS CoreDNS policy must select only kube-dns pods")
    if set(spec.get("policyTypes", [])) != {"Ingress", "Egress"}:
        fail("AWS CoreDNS policy must control ingress and egress")

    expected_worker_sources = [
        {"ipBlock": {"cidr": "10.40.10.0/24"}},
        {"ipBlock": {"cidr": "10.40.11.0/24"}},
    ]
    expected_health_ports = [
        {"protocol": "TCP", "port": 8080},
        {"protocol": "TCP", "port": 8181},
    ]
    if spec.get("ingress") != [
        {"from": expected_worker_sources, "ports": expected_health_ports}
    ]:
        fail("AWS CoreDNS ingress must allow only private-node health probes")

    expected_egress = [
        {
            "to": [{"ipBlock": {"cidr": "172.20.0.1/32"}}],
            "ports": [{"protocol": "TCP", "port": 443}],
        },
        {
            "to": [{"ipBlock": {"cidr": "10.40.0.2/32"}}],
            "ports": [
                {"protocol": "UDP", "port": 53},
                {"protocol": "TCP", "port": 53},
            ],
        },
    ]
    if spec.get("egress") != expected_egress:
        fail("AWS CoreDNS egress must allow only the API VIP and VPC resolver")


def main() -> None:
    if not ROOT.is_dir() or not AWS_OVERLAY.is_file() or not AWS_COREDNS_POLICY.is_file():
        fail("expected base and AWS overlay directories")
    documents = load_documents()
    validate_namespaces(documents)
    validate_deployments(documents)
    validate_services(documents)
    validate_network_policies(documents)
    validate_no_committed_secrets(documents)
    validate_aws_overlay()
    validate_aws_coredns_policy()
    print(
        "Validated Kubernetes namespaces, hardened workloads, internal services, "
        "default-deny policies, and immutable AWS images."
    )


if __name__ == "__main__":
    main()
