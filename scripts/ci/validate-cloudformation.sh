#!/usr/bin/env bash
set -euo pipefail

python - <<'PY'
from pathlib import Path
from typing import Any

import yaml


class CloudFormationLoader(yaml.SafeLoader):
    pass


def construct_intrinsic(
    loader: CloudFormationLoader,
    tag_suffix: str,
    node: yaml.Node,
) -> dict[str, Any]:
    if isinstance(node, yaml.ScalarNode):
        value = loader.construct_scalar(node)
    elif isinstance(node, yaml.SequenceNode):
        value = loader.construct_sequence(node)
    else:
        value = loader.construct_mapping(node)
    return {f"!{tag_suffix}": value}


CloudFormationLoader.add_multi_constructor("!", construct_intrinsic)

root = Path("infra/cloudformation/bootstrap")
templates: dict[str, dict[str, Any]] = {}
for path in sorted(root.glob("*.yaml")):
    document = yaml.load(path.read_text(encoding="utf-8"), Loader=CloudFormationLoader)
    if not isinstance(document, dict) or not isinstance(document.get("Resources"), dict):
        raise SystemExit(f"{path}: expected a CloudFormation object with Resources")
    templates[path.name] = document

name = "github-oidc-plan-role.yaml"
template = templates.get(name)
if template is None:
    raise SystemExit(f"missing required template: {root / name}")

resources = template["Resources"]
expected_resources = {"GitHubOidcProvider", "GitHubPlanPolicy", "GitHubPlanRole"}
if set(resources) != expected_resources:
    raise SystemExit(f"{name}: resource set must be exactly {sorted(expected_resources)}")

for logical_id, resource in resources.items():
    if resource.get("DeletionPolicy") != "Retain":
        raise SystemExit(f"{name}: {logical_id} must use DeletionPolicy Retain")
    if resource.get("UpdateReplacePolicy") != "Retain":
        raise SystemExit(f"{name}: {logical_id} must use UpdateReplacePolicy Retain")

provider = resources["GitHubOidcProvider"]["Properties"]
if provider.get("Url") != "https://token.actions.githubusercontent.com":
    raise SystemExit(f"{name}: unexpected OIDC provider URL")
if provider.get("ClientIdList") != ["sts.amazonaws.com"]:
    raise SystemExit(f"{name}: OIDC audience must be exactly sts.amazonaws.com")
if "ThumbprintList" in provider:
    raise SystemExit(f"{name}: let IAM retrieve the current CA thumbprint")

repository_parameter = template["Parameters"]["GitHubRepository"]
immutable_repository = "AnouarMohamed@235483559/grid-scada-security@1307773501"
if repository_parameter.get("Default") != immutable_repository:
    raise SystemExit(f"{name}: immutable GitHub repository identifier changed")
if "@[0-9]+" not in repository_parameter.get("AllowedPattern", ""):
    raise SystemExit(f"{name}: GitHub repository parameter must require immutable IDs")

role = resources["GitHubPlanRole"]["Properties"]
policy_ref = {"!Ref": "GitHubPlanPolicy"}
if role.get("ManagedPolicyArns") != [policy_ref]:
    raise SystemExit(f"{name}: role must attach only GitHubPlanPolicy")
if role.get("PermissionsBoundary") != policy_ref:
    raise SystemExit(f"{name}: GitHubPlanPolicy must also be the permissions boundary")
if role.get("Path") != "/gridguard/" or role.get("MaxSessionDuration") != 3600:
    raise SystemExit(f"{name}: role path or session duration changed unexpectedly")
if "Policies" in role:
    raise SystemExit(f"{name}: inline role policies are not permitted")

trust = role["AssumeRolePolicyDocument"]["Statement"]
if len(trust) != 1:
    raise SystemExit(f"{name}: role trust must contain exactly one statement")
trust_statement = trust[0]
if trust_statement.get("Action") != "sts:AssumeRoleWithWebIdentity":
    raise SystemExit(f"{name}: trust action must be AssumeRoleWithWebIdentity")
if trust_statement.get("Effect") != "Allow":
    raise SystemExit(f"{name}: trust statement must be Allow")
if trust_statement.get("Principal") != {"Federated": {"!Ref": "GitHubOidcProvider"}}:
    raise SystemExit(f"{name}: trust principal must be only the template OIDC provider")
conditions = trust_statement.get("Condition", {}).get("StringEquals", {})
expected_condition_keys = {
    "token.actions.githubusercontent.com:aud",
    "token.actions.githubusercontent.com:sub",
}
if set(conditions) != expected_condition_keys:
    raise SystemExit(f"{name}: trust must bind only exact audience and subject claims")
if conditions["token.actions.githubusercontent.com:aud"] != "sts.amazonaws.com":
    raise SystemExit(f"{name}: trust audience is not sts.amazonaws.com")
expected_subject = {"!Sub": "repo:${GitHubRepository}:environment:${GitHubEnvironment}"}
if conditions["token.actions.githubusercontent.com:sub"] != expected_subject:
    raise SystemExit(f"{name}: trust subject is not the exact repository environment")

statements = resources["GitHubPlanPolicy"]["Properties"]["PolicyDocument"]["Statement"]
by_sid = {statement["Sid"]: statement for statement in statements}
if len(by_sid) != len(statements):
    raise SystemExit(f"{name}: policy statement Sids must be unique")
expected_sids = {
    "ReadStateBucketMetadata",
    "ListExactStateObjects",
    "ReadExactState",
    "ManageExactStateLock",
    "UseStateEncryptionKey",
    "DenyStateMutation",
    "DenyPrivilegeAndSecretAccess",
    "ReadTerraformMetadata",
}
if set(by_sid) != expected_sids:
    raise SystemExit(f"{name}: unexpected policy statement set")

bucket_arn = {"!Sub": "arn:${AWS::Partition}:s3:::${StateBucketName}"}
state_arn = {"!Sub": "arn:${AWS::Partition}:s3:::${StateBucketName}/${StateKey}"}
lock_arn = {"!Sub": "arn:${AWS::Partition}:s3:::${StateBucketName}/${StateKey}.tflock"}


def require_statement(
    sid: str,
    effect: str,
    actions: set[str],
    resource: object,
) -> dict[str, Any]:
    statement = by_sid[sid]
    actual_actions = statement["Action"]
    actual = set(actual_actions if isinstance(actual_actions, list) else [actual_actions])
    if statement.get("Effect") != effect or actual != actions:
        raise SystemExit(f"{name}: {sid} effect or actions changed unexpectedly")
    if statement.get("Resource") != resource:
        raise SystemExit(f"{name}: {sid} resource boundary changed unexpectedly")
    return statement


require_statement(
    "ReadStateBucketMetadata",
    "Allow",
    {"s3:GetBucketLocation", "s3:GetBucketVersioning"},
    bucket_arn,
)
list_statement = require_statement(
    "ListExactStateObjects", "Allow", {"s3:ListBucket"}, bucket_arn
)
expected_prefixes = [{"!Ref": "StateKey"}, {"!Sub": "${StateKey}.tflock"}]
if list_statement.get("Condition") != {
    "StringEquals": {"s3:prefix": expected_prefixes}
}:
    raise SystemExit(f"{name}: state bucket list prefixes changed unexpectedly")
require_statement(
    "ReadExactState",
    "Allow",
    {"s3:GetObject", "s3:GetObjectVersion"},
    state_arn,
)
require_statement(
    "ManageExactStateLock",
    "Allow",
    {"s3:DeleteObject", "s3:GetObject", "s3:PutObject"},
    lock_arn,
)
require_statement(
    "UseStateEncryptionKey",
    "Allow",
    {"kms:Decrypt", "kms:DescribeKey", "kms:Encrypt", "kms:GenerateDataKey"},
    {"!Ref": "StateKmsKeyArn"},
)
require_statement(
    "DenyStateMutation",
    "Deny",
    {"s3:DeleteObject", "s3:DeleteObjectVersion", "s3:PutObject"},
    state_arn,
)
require_statement(
    "DenyPrivilegeAndSecretAccess",
    "Deny",
    {"iam:PassRole", "secretsmanager:GetSecretValue", "sts:AssumeRole"},
    "*",
)
expected_metadata_actions = {
    "ec2:Describe*",
    "ec2:GetManagedPrefixListEntries",
    "ecr:Describe*",
    "ecr:GetLifecyclePolicy",
    "ecr:GetRegistryPolicy",
    "ecr:GetRegistryScanningConfiguration",
    "ecr:ListImages",
    "ecr:ListTagsForResource",
    "ecs:Describe*",
    "ecs:List*",
    "elasticfilesystem:Describe*",
    "elasticloadbalancing:Describe*",
    "iam:GetOpenIDConnectProvider",
    "iam:GetPolicy",
    "iam:GetPolicyVersion",
    "iam:GetRole",
    "iam:GetRolePolicy",
    "iam:ListAttachedRolePolicies",
    "iam:ListInstanceProfilesForRole",
    "iam:ListOpenIDConnectProviders",
    "iam:ListPolicyTags",
    "iam:ListPolicyVersions",
    "iam:ListRolePolicies",
    "iam:ListRoleTags",
    "logs:Describe*",
    "logs:GetDataProtectionPolicy",
    "logs:ListTagsForResource",
    "secretsmanager:DescribeSecret",
    "secretsmanager:GetResourcePolicy",
    "secretsmanager:ListSecrets",
    "secretsmanager:ListSecretVersionIds",
    "servicediscovery:Get*",
    "servicediscovery:List*",
    "sts:GetCallerIdentity",
}
require_statement(
    "ReadTerraformMetadata", "Allow", expected_metadata_actions, "*"
)

name = "github-oidc-image-evidence-role.yaml"
template = templates.get(name)
if template is None:
    raise SystemExit(f"missing required template: {root / name}")

resources = template["Resources"]
expected_resources = {"GitHubImageEvidencePolicy", "GitHubImageEvidenceRole"}
if set(resources) != expected_resources:
    raise SystemExit(f"{name}: resource set must be exactly {sorted(expected_resources)}")

for logical_id, resource in resources.items():
    if resource.get("DeletionPolicy") != "Retain":
        raise SystemExit(f"{name}: {logical_id} must use DeletionPolicy Retain")
    if resource.get("UpdateReplacePolicy") != "Retain":
        raise SystemExit(f"{name}: {logical_id} must use UpdateReplacePolicy Retain")

immutable_repository = "AnouarMohamed@235483559/grid-scada-security@1307773501"
repository_parameter = template["Parameters"]["GitHubRepository"]
if repository_parameter.get("Default") != immutable_repository:
    raise SystemExit(f"{name}: immutable GitHub repository identifier changed")
if template["Parameters"]["GitHubEnvironment"].get("Default") != "sandbox":
    raise SystemExit(f"{name}: GitHub environment must default to sandbox")
if template["Parameters"]["RepositoryPrefix"].get("Default") != "gridguard-aws-sandbox":
    raise SystemExit(f"{name}: unexpected ECR repository prefix")

role = resources["GitHubImageEvidenceRole"]["Properties"]
policy_ref = {"!Ref": "GitHubImageEvidencePolicy"}
if role.get("ManagedPolicyArns") != [policy_ref]:
    raise SystemExit(f"{name}: role must attach only GitHubImageEvidencePolicy")
if role.get("PermissionsBoundary") != policy_ref:
    raise SystemExit(f"{name}: evidence policy must also be the permissions boundary")
if role.get("Path") != "/gridguard/" or role.get("MaxSessionDuration") != 3600:
    raise SystemExit(f"{name}: role path or session duration changed unexpectedly")
if "Policies" in role:
    raise SystemExit(f"{name}: inline role policies are not permitted")

trust = role["AssumeRolePolicyDocument"]["Statement"]
if len(trust) != 1:
    raise SystemExit(f"{name}: role trust must contain exactly one statement")
trust_statement = trust[0]
if trust_statement.get("Action") != "sts:AssumeRoleWithWebIdentity":
    raise SystemExit(f"{name}: trust action must be AssumeRoleWithWebIdentity")
if trust_statement.get("Effect") != "Allow":
    raise SystemExit(f"{name}: trust statement must be Allow")
if trust_statement.get("Principal") != {"Federated": {"!Ref": "GitHubOidcProviderArn"}}:
    raise SystemExit(f"{name}: trust principal must be the supplied OIDC provider")
conditions = trust_statement.get("Condition", {}).get("StringEquals", {})
expected_conditions = {
    "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
    "token.actions.githubusercontent.com:sub": {
        "!Sub": "repo:${GitHubRepository}:environment:${GitHubEnvironment}"
    },
}
if conditions != expected_conditions:
    raise SystemExit(f"{name}: trust must bind the exact audience and environment subject")

statements = resources["GitHubImageEvidencePolicy"]["Properties"]
statements = statements["PolicyDocument"]["Statement"]
by_sid = {statement["Sid"]: statement for statement in statements}
if len(by_sid) != len(statements):
    raise SystemExit(f"{name}: policy statement Sids must be unique")
expected_sids = {
    "AuthenticateToEcr",
    "PullExactImageRepositories",
    "ReadCallerIdentity",
    "DenyEcrMutation",
    "DenyPrivilegeAndSecretAccess",
}
if set(by_sid) != expected_sids:
    raise SystemExit(f"{name}: unexpected policy statement set")


def require_evidence_statement(
    sid: str,
    effect: str,
    actions: set[str],
    resource: object,
) -> dict[str, Any]:
    statement = by_sid[sid]
    actual_actions = statement["Action"]
    actual = set(actual_actions if isinstance(actual_actions, list) else [actual_actions])
    if statement.get("Effect") != effect or actual != actions:
        raise SystemExit(f"{name}: {sid} effect or actions changed unexpectedly")
    if statement.get("Resource") != resource:
        raise SystemExit(f"{name}: {sid} resource boundary changed unexpectedly")
    return statement


require_evidence_statement(
    "AuthenticateToEcr", "Allow", {"ecr:GetAuthorizationToken"}, "*"
)
repository_arns = [
    {
        "!Sub": (
            "arn:${AWS::Partition}:ecr:${AWS::Region}:${AWS::AccountId}:"
            f"repository/${{RepositoryPrefix}}/{component}"
        )
    }
    for component in ("power-sim", "modbus-ingestor", "influxdb", "grafana")
]
require_evidence_statement(
    "PullExactImageRepositories",
    "Allow",
    {
        "ecr:BatchCheckLayerAvailability",
        "ecr:BatchGetImage",
        "ecr:DescribeImages",
        "ecr:GetDownloadUrlForLayer",
    },
    repository_arns,
)
require_evidence_statement(
    "ReadCallerIdentity", "Allow", {"sts:GetCallerIdentity"}, "*"
)
require_evidence_statement(
    "DenyEcrMutation",
    "Deny",
    {
        "ecr:BatchDeleteImage",
        "ecr:CompleteLayerUpload",
        "ecr:CreateRepository",
        "ecr:DeleteLifecyclePolicy",
        "ecr:DeleteRegistryPolicy",
        "ecr:DeleteRepository",
        "ecr:DeleteRepositoryPolicy",
        "ecr:InitiateLayerUpload",
        "ecr:PutImage",
        "ecr:PutImageScanningConfiguration",
        "ecr:PutImageTagMutability",
        "ecr:PutLifecyclePolicy",
        "ecr:PutRegistryPolicy",
        "ecr:PutRegistryScanningConfiguration",
        "ecr:PutReplicationConfiguration",
        "ecr:ReplicateImage",
        "ecr:SetRepositoryPolicy",
        "ecr:StartImageScan",
        "ecr:TagResource",
        "ecr:UntagResource",
        "ecr:UploadLayerPart",
    },
    "*",
)
require_evidence_statement(
    "DenyPrivilegeAndSecretAccess",
    "Deny",
    {"iam:PassRole", "secretsmanager:GetSecretValue", "sts:AssumeRole"},
    "*",
)

name = "state-backend.yaml"
template = templates.get(name)
if template is None:
    raise SystemExit(f"missing required template: {root / name}")
if template["Parameters"]["StateKey"].get("Default") != (
    "gridguard/aws-sandbox/terraform.tfstate"
):
    raise SystemExit(f"{name}: sandbox state key changed unexpectedly")
if template["Parameters"]["EksStateKey"].get("Default") != (
    "gridguard/aws-eks-lab/terraform.tfstate"
):
    raise SystemExit(f"{name}: EKS state key changed unexpectedly")

state_statements = template["Resources"]["StateAccessPolicy"]["Properties"]
state_statements = state_statements["PolicyDocument"]["Statement"]
state_by_sid = {statement["Sid"]: statement for statement in state_statements}
expected_prefixes = [
    {"!Ref": "StateKey"},
    {"!Sub": "${StateKey}.tflock"},
    {"!Ref": "EksStateKey"},
    {"!Sub": "${EksStateKey}.tflock"},
]
actual_prefixes = state_by_sid["ListStateObjects"]["Condition"]["StringEquals"]
if actual_prefixes.get("s3:prefix") != expected_prefixes:
    raise SystemExit(f"{name}: state list access must cover exactly two state keys")
expected_state_objects = [
    {"!Sub": "${StateBucket.Arn}/${StateKey}"},
    {"!Sub": "${StateBucket.Arn}/${StateKey}.tflock"},
    {"!Sub": "${StateBucket.Arn}/${EksStateKey}"},
    {"!Sub": "${StateBucket.Arn}/${EksStateKey}.tflock"},
]
if state_by_sid["ReadWriteState"].get("Resource") != expected_state_objects:
    raise SystemExit(f"{name}: read/write access must cover exactly two states and locks")
expected_lock_objects = [
    {"!Sub": "${StateBucket.Arn}/${StateKey}.tflock"},
    {"!Sub": "${StateBucket.Arn}/${EksStateKey}.tflock"},
]
if state_by_sid["DeleteLockOnly"].get("Resource") != expected_lock_objects:
    raise SystemExit(f"{name}: delete access must remain limited to two lock objects")

name = "eks-lab-deployment-policy.yaml"
template = templates.get(name)
if template is None:
    raise SystemExit(f"missing required template: {root / name}")

resources = template["Resources"]
expected_resources = {"EksLabDeploymentPolicy", "EksLabRoleBoundary"}
if set(resources) != expected_resources:
    raise SystemExit(f"{name}: resource set must be exactly {sorted(expected_resources)}")

deployment_properties = resources["EksLabDeploymentPolicy"]["Properties"]
if deployment_properties.get("Roles") != [{"!Ref": "DeploymentRoleName"}]:
    raise SystemExit(f"{name}: deployment policy must attach only to DeploymentRoleName")

statements = deployment_properties["PolicyDocument"]["Statement"]
by_sid = {statement["Sid"]: statement for statement in statements}
expected_sids = {
    "ReadEksLabMetadata",
    "ManageExactEksCluster",
    "ManageExactEksNodeGroup",
    "ManageExactVpcCniAddon",
    "ManageExactEksAccessEntry",
    "ManageEksPrivateEndpoints",
    "ManageEksEndpointSecurityGroup",
    "ManageEksControlPlaneLogs",
    "CreateBoundedEksRoles",
    "ManageBoundedEksRoles",
    "AttachReviewedEksPolicies",
    "PassExactEksRoles",
    "CreateRequiredServiceLinkedRoles",
}
if set(by_sid) != expected_sids or len(by_sid) != len(statements):
    raise SystemExit(f"{name}: unexpected or duplicate deployment-policy Sids")

for statement in statements:
    actions = statement["Action"]
    actions = actions if isinstance(actions, list) else [actions]
    if "*" in actions or "iam:*" in actions or "eks:*" in actions:
        raise SystemExit(f"{name}: {statement['Sid']} contains a wildcard action")
    if "secretsmanager:GetSecretValue" in actions:
        raise SystemExit(f"{name}: deployment policy cannot read secret values")

for sid in (
    "ManageExactEksCluster",
    "ManageExactEksNodeGroup",
    "ManageExactVpcCniAddon",
    "ManageExactEksAccessEntry",
):
    serialized = str(by_sid[sid].get("Resource"))
    if "gridguard-aws-eks-lab" not in serialized:
        raise SystemExit(f"{name}: {sid} is not scoped to the exact cluster name")

create_roles = by_sid["CreateBoundedEksRoles"]
expected_boundary = {"!Ref": "EksLabRoleBoundary"}
actual_boundary = create_roles.get("Condition", {}).get("ArnEquals", {}).get(
    "iam:PermissionsBoundary"
)
if actual_boundary != expected_boundary:
    raise SystemExit(f"{name}: EKS role creation must require EksLabRoleBoundary")

attachment_condition = by_sid["AttachReviewedEksPolicies"]["Condition"]["ArnEquals"]
policy_arns = attachment_condition["iam:PolicyARN"]
if len(policy_arns) != 4:
    raise SystemExit(f"{name}: exactly four reviewed AWS managed policies are allowed")

boundary_statements = resources["EksLabRoleBoundary"]["Properties"]
boundary_statements = boundary_statements["PolicyDocument"]["Statement"]
boundary_by_sid = {statement["Sid"]: statement for statement in boundary_statements}
expected_boundary_sids = {
    "DescribeEksRuntime",
    "ManagePodNetworkInterfaces",
    "TagEksRuntimeNetworkResources",
    "AuthenticateToEcr",
    "PullGridGuardImages",
    "PullEksSystemImages",
}
if set(boundary_by_sid) != expected_boundary_sids:
    raise SystemExit(f"{name}: unexpected EKS role-boundary statement set")
for statement in boundary_statements:
    actions = statement["Action"]
    actions = actions if isinstance(actions, list) else [actions]
    if "*" in actions or any(action.startswith("iam:") for action in actions):
        raise SystemExit(f"{name}: role boundary cannot grant wildcard or IAM actions")

expected_runtime_reads = {
    "ec2:DescribeAvailabilityZones",
    "ec2:DescribeDhcpOptions",
    "ec2:DescribeInstances",
    "ec2:DescribeInstanceTopology",
    "ec2:DescribeInstanceTypes",
    "ec2:DescribeNetworkInterfaces",
    "ec2:DescribeRouteTables",
    "ec2:DescribeSecurityGroups",
    "ec2:DescribeSubnets",
    "ec2:DescribeTags",
    "ec2:DescribeVolumes",
    "ec2:DescribeVolumesModifications",
    "ec2:DescribeVpcs",
    "eks:DescribeCluster",
    "eks-auth:AssumeRoleForPodIdentity",
    "kms:DescribeKey",
}
actual_runtime_reads = set(boundary_by_sid["DescribeEksRuntime"]["Action"])
if actual_runtime_reads != expected_runtime_reads:
    raise SystemExit(f"{name}: reviewed EKS runtime read set changed")

expected_ecr_pull_actions = {
    "ecr:BatchCheckLayerAvailability",
    "ecr:BatchGetImage",
    "ecr:GetDownloadUrlForLayer",
}
for sid in ("PullGridGuardImages", "PullEksSystemImages"):
    if set(boundary_by_sid[sid]["Action"]) != expected_ecr_pull_actions:
        raise SystemExit(f"{name}: {sid} read-only action set changed")

expected_system_image_resources = [
    {
        "!Sub": "arn:${AWS::Partition}:ecr:${AWS::Region}:602401143452:repository/amazon/aws-network-policy-agent"
    },
    {
        "!Sub": "arn:${AWS::Partition}:ecr:${AWS::Region}:602401143452:repository/amazon-k8s-cni"
    },
    {
        "!Sub": "arn:${AWS::Partition}:ecr:${AWS::Region}:602401143452:repository/amazon-k8s-cni-init"
    },
    {
        "!Sub": "arn:${AWS::Partition}:ecr:${AWS::Region}:602401143452:repository/eks/coredns"
    },
    {
        "!Sub": "arn:${AWS::Partition}:ecr:${AWS::Region}:602401143452:repository/eks/kube-proxy"
    },
]
if boundary_by_sid["PullEksSystemImages"].get("Resource") != expected_system_image_resources:
    raise SystemExit(f"{name}: EKS system-image repository scope changed")

expected_eni_actions = {
    "ec2:AssignPrivateIpAddresses",
    "ec2:AttachNetworkInterface",
    "ec2:CreateNetworkInterface",
    "ec2:DeleteNetworkInterface",
    "ec2:DetachNetworkInterface",
    "ec2:ModifyNetworkInterfaceAttribute",
    "ec2:UnassignPrivateIpAddresses",
}
actual_eni_actions = set(boundary_by_sid["ManagePodNetworkInterfaces"]["Action"])
if actual_eni_actions != expected_eni_actions:
    raise SystemExit(f"{name}: reviewed VPC CNI mutation set changed")

expected_tag_resources = [
    {
        "!Sub": "arn:${AWS::Partition}:ec2:${AWS::Region}:${AWS::AccountId}:instance/*"
    },
    {
        "!Sub": "arn:${AWS::Partition}:ec2:${AWS::Region}:${AWS::AccountId}:network-interface/*"
    },
]
tag_statement = boundary_by_sid["TagEksRuntimeNetworkResources"]
if tag_statement.get("Action") != "ec2:CreateTags":
    raise SystemExit(f"{name}: EKS runtime tagging action changed")
if tag_statement.get("Resource") != expected_tag_resources:
    raise SystemExit(f"{name}: EKS runtime tagging scope changed")

print(f"Validated {len(templates)} CloudFormation bootstrap templates.")
print("Validated plan-only OIDC trust, state boundary, and action boundary.")
print("Validated read-only image-evidence trust and four-repository boundary.")
print("Validated exact-object access for the sandbox and EKS state backends.")
print("Validated temporary EKS role boundary and deployment-policy scope.")
PY
