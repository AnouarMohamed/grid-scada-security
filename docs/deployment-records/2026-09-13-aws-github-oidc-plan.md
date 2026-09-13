# AWS GitHub OIDC Plan Identity Record

## Scope

The GridGuard plan-only GitHub Actions identity was deployed and verified in
the dedicated `us-east-1` sandbox on 2026-09-13. This record contains no
credentials, tokens, secret values, state contents, or complete account-scoped
resource inventory.

Repository changes were reviewed through:

- [PR 44](https://github.com/AnouarMohamed/grid-scada-security/pull/44), which
  added the retained bootstrap, exact policy checks, plan-only workflow, and
  owner runbook.
- [PR 45](https://github.com/AnouarMohamed/grid-scada-security/pull/45), which
  corrected the trust to GitHub's immutable owner and repository IDs.

## Deployed Boundary

CloudFormation stack `gridguard-github-oidc-plan` reached `UPDATE_COMPLETE`
with termination protection enabled. CloudFormation owns and retains exactly:

| Logical resource | Type | Purpose |
| --- | --- | --- |
| `GitHubOidcProvider` | `AWS::IAM::OIDCProvider` | Account-wide GitHub token issuer with only `sts.amazonaws.com` as client ID |
| `GitHubPlanPolicy` | `AWS::IAM::ManagedPolicy` | Exact state read, exact lock management, state-key KMS use, and AWS metadata reads |
| `GitHubPlanRole` | `AWS::IAM::Role` | Plan-only web-identity role using the same policy as its permissions boundary |

The final trust accepts only:

```text
aud = sts.amazonaws.com
sub = repo:AnouarMohamed@235483559/grid-scada-security@1307773501:environment:sandbox
```

The immutable numeric identifiers prevent a renamed or recycled GitHub
namespace from inheriting this trust. GitHub's repository OIDC API reported
`use_immutable_subject: true` and the matching `sub_claim_prefix`.

The role has one attached policy and one permissions-boundary use. The policy
permits reading the exact Terraform state object, writing only its exact
`.tflock`, using only the state KMS key, and reading metadata required during
refresh. It explicitly denies state mutation, secret-value access, role
passing, and role chaining. It grants no infrastructure mutation actions.

## Review And Validation

Before initial execution, the CloudFormation change set contained exactly
three additions and no replacement or deletion. The immutable-subject
correction change set contained exactly one in-place modification to
`GitHubPlanRole.AssumeRolePolicyDocument`; the provider and policy did not
change.

Validation evidence:

- AWS CloudFormation accepted the template.
- IAM Access Analyzer returned zero policy findings.
- Offline CI asserted the exact provider, audience, immutable subject,
  state/lock resources, allowed actions, explicit denies, and permissions
  boundary.
- Twelve mocked Terraform tests passed, including immutable-subject regression
  coverage.
- Both change sets were owner-reviewed before execution.
- The owner browser-issued CLI session was closed after each IAM operation.

## Authentication Exercise

The first manual workflow run failed during OIDC assumption because GitHub
issued its immutable 2026 subject format while the initial role trusted the
legacy name-only format. CloudTrail showed the immutable owner and repository
IDs and an `AccessDenied` result. Terraform had not initialized, and neither
state nor infrastructure was changed.

After PR 45 and the role-only CloudFormation update, manual run
[`34766574183`](https://github.com/AnouarMohamed/grid-scada-security/actions/runs/34766574183)
succeeded from protected `main`. The run:

1. Obtained short-lived AWS credentials through GitHub OIDC.
2. Initialized the KMS-encrypted S3 backend.
3. Completed with Terraform's native S3 lockfile enabled for the exact key.
4. Refreshed the deployed foundation using metadata-only permissions.
5. Reported `No changes. Your infrastructure matches the configuration.`
6. Exited without any Terraform apply step.

After the deployment workflow moved to the official Node 24
`aws-actions/configure-aws-credentials` v6.2.4 commit, final run
[`34767027873`](https://github.com/AnouarMohamed/grid-scada-security/actions/runs/34767027873)
also completed with no changes. It enforced the expected AWS account, masked
the account after authentication, and used the auditable STS session name
`gridguard-plan-34767027873`. The earlier Node 20 deprecation warning was no
longer present.

The GitHub `sandbox` environment is restricted to protected branches and holds
one role secret plus the five non-secret backend/configuration variables. No
static AWS access key is stored in GitHub.

## Current State

The OIDC plan path is operational and drift-free. The workflow cannot apply
Terraform, and the role cannot mutate infrastructure. Billable runtime
resources remain disabled; ECS has zero services and zero running tasks.

Before runtime can be enabled, the project still requires a separately
reviewed apply identity and environment approval, closure or explicit
time-bounded acceptance of remaining image findings, signed SBOM provenance,
the private Grafana operator path, and the documented secret-value procedure.
