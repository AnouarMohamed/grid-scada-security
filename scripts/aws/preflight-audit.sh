#!/usr/bin/env bash
set -euo pipefail

: "${AWS_PROFILE:?Set AWS_PROFILE to the non-root AWS CLI profile to audit.}"

readonly AWS_REGION="${AWS_REGION:-us-east-1}"
readonly AWS_BUDGET_NAME="${AWS_BUDGET_NAME:-gridguard-gross-usage}"
readonly AWS_AUDIT_ALL_REGIONS="${AWS_AUDIT_ALL_REGIONS:-false}"
export AWS_PAGER=""

failures=0
warnings=0

pass() {
  printf 'PASS  %s\n' "$*"
}

warn() {
  printf 'WARN  %s\n' "$*"
  warnings=$((warnings + 1))
}

fail() {
  printf 'FAIL  %s\n' "$*" >&2
  failures=$((failures + 1))
}

aws_read() {
  aws --profile "${AWS_PROFILE}" --region "${AWS_REGION}" --no-cli-pager "$@"
}

read_count() {
  local label="$1"
  local query="$2"
  shift 2

  local count
  if ! count="$(aws_read "$@" --query "${query}" --output text 2>/dev/null)"; then
    fail "${label}: API check failed"
    return
  fi

  if [[ "${count}" == "0" || "${count}" == "None" ]]; then
    pass "${label}: none"
  else
    warn "${label}: ${count} found; review before applying Terraform"
  fi
}

for command in aws jq; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    printf 'ERROR Required command not found: %s\n' "${command}" >&2
    exit 2
  fi
done

printf 'GridGuard AWS preflight (read-only)\n'
printf 'Profile: %s | Region: %s | Budget: %s\n\n' \
  "${AWS_PROFILE}" "${AWS_REGION}" "${AWS_BUDGET_NAME}"

identity_json="$(aws_read sts get-caller-identity --output json)"
account_id="$(jq -r '.Account' <<<"${identity_json}")"
principal_arn="$(jq -r '.Arn' <<<"${identity_json}")"
principal_name="${principal_arn##*/}"

if [[ "${principal_arn}" == *":root" ]]; then
  fail "caller identity is root; log out and authenticate with a non-root principal"
else
  pass "caller is ${principal_name} in account ...${account_id: -4}"
fi

summary_json="$(aws_read iam get-account-summary --output json)"
if [[ "$(jq -r '.SummaryMap.AccountMFAEnabled // 0' <<<"${summary_json}")" == "1" ]]; then
  pass "root MFA is enabled"
else
  fail "root MFA is not enabled"
fi

if [[ "$(jq -r '.SummaryMap.AccountAccessKeysPresent // 0' <<<"${summary_json}")" == "0" ]]; then
  pass "root has no access keys"
else
  fail "root access keys exist"
fi

if [[ "${principal_arn}" == arn:aws:iam::*:user/* ]]; then
  mfa_count="$(aws_read iam list-mfa-devices \
    --user-name "${principal_name}" --query 'length(MFADevices)' --output text)"
  key_count="$(aws_read iam list-access-keys \
    --user-name "${principal_name}" --query 'length(AccessKeyMetadata)' --output text)"

  if ((mfa_count > 0)); then
    pass "${principal_name} has an MFA device"
  else
    fail "${principal_name} has no MFA device"
  fi

  if ((key_count == 0)); then
    pass "${principal_name} has no long-lived access keys"
  else
    fail "${principal_name} has ${key_count} long-lived access key(s)"
  fi
else
  warn "caller is not a direct IAM user; verify MFA in the identity provider"
fi

if password_json="$(aws_read iam get-account-password-policy --output json 2>/dev/null)"; then
  if jq -e '
    .PasswordPolicy.MinimumPasswordLength >= 16 and
    .PasswordPolicy.RequireSymbols == true and
    .PasswordPolicy.RequireNumbers == true and
    .PasswordPolicy.RequireUppercaseCharacters == true and
    .PasswordPolicy.RequireLowercaseCharacters == true and
    .PasswordPolicy.AllowUsersToChangePassword == true and
    .PasswordPolicy.PasswordReusePrevention >= 24 and
    (.PasswordPolicy.ExpirePasswords // false) == false
  ' >/dev/null <<<"${password_json}"; then
    pass "IAM password policy meets the GridGuard baseline"
  else
    fail "IAM password policy does not meet the GridGuard baseline"
  fi
else
  fail "no custom IAM password policy is configured"
fi

plan_json="$(aws_read freetier get-account-plan-state --output json)"
plan_type="$(jq -r '.accountPlanType' <<<"${plan_json}")"
plan_status="$(jq -r '.accountPlanStatus' <<<"${plan_json}")"
credits="$(jq -r '.accountPlanRemainingCredits.amount' <<<"${plan_json}")"
expires="$(jq -r '.accountPlanExpirationDate' <<<"${plan_json}")"
if [[ "${plan_type}" == "FREE" && "${plan_status}" == "ACTIVE" ]]; then
  pass "Free plan is active; remaining credits: USD ${credits}; expires: ${expires}"
else
  fail "unexpected account plan: ${plan_type}/${plan_status}"
fi

usage_count="$(aws_read freetier get-free-tier-usage \
  --query 'length(freeTierUsages[?actualUsageAmount > `0`])' --output text)"
if ((usage_count == 0)); then
  pass "Free Tier reports no metered usage"
else
  warn "Free Tier reports ${usage_count} nonzero usage record(s)"
fi

if budget_json="$(aws_read budgets describe-budget \
  --account-id "${account_id}" --budget-name "${AWS_BUDGET_NAME}" \
  --output json 2>/dev/null)"; then
  budget_limit="$(jq -r '.Budget.BudgetLimit | "\(.Amount) \(.Unit)"' <<<"${budget_json}")"
  legacy_excludes_credit="$(jq -r '.Budget.CostTypes.IncludeCredit? == false' <<<"${budget_json}")"
  uses_unblended_cost="$(jq -r '
    [.Budget.Metrics[]? | ascii_downcase]
    | any(. == "unblendedcost" or . == "unblended_cost")
  ' <<<"${budget_json}")"
  pass "budget ${AWS_BUDGET_NAME} exists with limit ${budget_limit}"

  if [[ "${legacy_excludes_credit}" == "true" ]]; then
    pass "budget excludes credits through the legacy cost-type setting"
  elif [[ "${uses_unblended_cost}" == "true" ]]; then
    pass "budget uses unblended cost and does not net promotional credits"
  else
    fail "budget can net credits; select Unblended cost or set CostTypes.IncludeCredit to false"
  fi

  notifications_json="$(aws_read budgets describe-notifications-for-budget \
    --account-id "${account_id}" --budget-name "${AWS_BUDGET_NAME}" \
    --output json)"
  notification_count="$(jq -r '.Notifications | length' <<<"${notifications_json}")"
  if ((notification_count > 0)); then
    pass "budget has ${notification_count} notification threshold(s)"

    subscriber_count=0
    while IFS=$'\t' read -r notification_type comparison_operator threshold; do
      current_subscribers="$(aws_read budgets describe-subscribers-for-notification \
        --account-id "${account_id}" --budget-name "${AWS_BUDGET_NAME}" \
        --notification "NotificationType=${notification_type},ComparisonOperator=${comparison_operator},Threshold=${threshold}" \
        --query 'length(Subscribers)' --output text)"
      subscriber_count=$((subscriber_count + current_subscribers))
    done < <(jq -r '.Notifications[] | [.NotificationType, .ComparisonOperator, .Threshold] | @tsv' \
      <<<"${notifications_json}")

    if ((subscriber_count > 0)); then
      pass "budget notifications have ${subscriber_count} subscriber assignment(s)"
    else
      fail "budget notifications have no subscribers"
    fi
  else
    fail "budget has no notification thresholds"
  fi
else
  fail "budget ${AWS_BUDGET_NAME} was not found or is not readable"
fi

az_count="$(aws_read ec2 describe-availability-zones \
  --filters Name=state,Values=available --query 'length(AvailabilityZones)' --output text)"
if ((az_count >= 2)); then
  pass "${AWS_REGION} has ${az_count} available zones"
else
  fail "${AWS_REGION} has fewer than two available zones"
fi

read_count "non-terminated EC2 instances in ${AWS_REGION}" \
  'length(Reservations[].Instances[?State.Name!=`terminated`][])' ec2 describe-instances
read_count "EBS volumes in ${AWS_REGION}" 'length(Volumes)' ec2 describe-volumes
read_count "Elastic IPs in ${AWS_REGION}" 'length(Addresses)' ec2 describe-addresses
read_count "active NAT gateways in ${AWS_REGION}" \
  'length(NatGateways[?State!=`deleted`])' ec2 describe-nat-gateways
read_count "VPC endpoints in ${AWS_REGION}" 'length(VpcEndpoints)' ec2 describe-vpc-endpoints
read_count "ECS clusters in ${AWS_REGION}" 'length(clusterArns)' ecs list-clusters
read_count "ECR repositories in ${AWS_REGION}" 'length(repositories)' ecr describe-repositories
read_count "load balancers in ${AWS_REGION}" 'length(LoadBalancers)' elbv2 describe-load-balancers
read_count "EFS filesystems in ${AWS_REGION}" 'length(FileSystems)' efs describe-file-systems
read_count "RDS instances in ${AWS_REGION}" 'length(DBInstances)' rds describe-db-instances
read_count "Lambda functions in ${AWS_REGION}" 'length(Functions)' lambda list-functions
read_count "CloudWatch log groups in ${AWS_REGION}" 'length(logGroups)' logs describe-log-groups
read_count "S3 buckets account-wide" 'length(Buckets)' s3api list-buckets
read_count "customer-created IAM roles account-wide" \
  'length(Roles[?Path!=`/aws-service-role/`])' iam list-roles

if [[ "${AWS_AUDIT_ALL_REGIONS}" == "true" ]]; then
  printf '\nAll-region core resource scan\n'
  mapfile -t regions < <(aws_read ec2 describe-regions --all-regions \
    --query 'Regions[?OptInStatus!=`not-opted-in`].RegionName' --output text | tr '\t' '\n')

  for audit_region in "${regions[@]}"; do
    region_total=0
    region_total=$((region_total + $(aws --profile "${AWS_PROFILE}" --region "${audit_region}" \
      ec2 describe-instances --query 'length(Reservations[].Instances[?State.Name!=`terminated`][])' \
      --output text --no-cli-pager)))
    region_total=$((region_total + $(aws --profile "${AWS_PROFILE}" --region "${audit_region}" \
      ec2 describe-volumes --query 'length(Volumes)' --output text --no-cli-pager)))
    region_total=$((region_total + $(aws --profile "${AWS_PROFILE}" --region "${audit_region}" \
      ec2 describe-addresses --query 'length(Addresses)' --output text --no-cli-pager)))
    region_total=$((region_total + $(aws --profile "${AWS_PROFILE}" --region "${audit_region}" \
      ec2 describe-nat-gateways --query 'length(NatGateways[?State!=`deleted`])' \
      --output text --no-cli-pager)))
    region_total=$((region_total + $(aws --profile "${AWS_PROFILE}" --region "${audit_region}" \
      ecs list-clusters --query 'length(clusterArns)' --output text --no-cli-pager)))
    region_total=$((region_total + $(aws --profile "${AWS_PROFILE}" --region "${audit_region}" \
      ecr describe-repositories --query 'length(repositories)' --output text --no-cli-pager)))
    region_total=$((region_total + $(aws --profile "${AWS_PROFILE}" --region "${audit_region}" \
      elbv2 describe-load-balancers --query 'length(LoadBalancers)' --output text --no-cli-pager)))
    region_total=$((region_total + $(aws --profile "${AWS_PROFILE}" --region "${audit_region}" \
      efs describe-file-systems --query 'length(FileSystems)' --output text --no-cli-pager)))
    region_total=$((region_total + $(aws --profile "${AWS_PROFILE}" --region "${audit_region}" \
      rds describe-db-instances --query 'length(DBInstances)' --output text --no-cli-pager)))
    region_total=$((region_total + $(aws --profile "${AWS_PROFILE}" --region "${audit_region}" \
      lambda list-functions --query 'length(Functions)' --output text --no-cli-pager)))

    if ((region_total == 0)); then
      pass "${audit_region}: no core billable resources"
    else
      warn "${audit_region}: ${region_total} core billable resource(s) found"
    fi
  done
fi

printf '\nResult: %s failure(s), %s warning(s)\n' "${failures}" "${warnings}"
if ((failures > 0)); then
  exit 1
fi
