.PHONY: ci docs cloudformation python workflows modbus-contracts terraform docker hygiene aws-preflight aws-state-bootstrap-validate aws-foundation-bootstrap-validate aws-github-oidc-bootstrap-validate aws-image-evidence-bootstrap-validate stack-up stack-modbus-up stack-live-up stack-naive-up stack-stealthy-up stack-down stack-reset stack-logs stack-ps stack-smoke stack-modbus-smoke stack-live-smoke stack-attack-smoke stack-naive-smoke stack-stealthy-smoke stack-dashboard-smoke

ci:
	bash scripts/ci/all.sh

hygiene:
	bash scripts/ci/validate-repo-hygiene.sh

docs:
	bash scripts/ci/validate-docs.sh

cloudformation:
	bash scripts/ci/validate-cloudformation.sh

python:
	bash scripts/ci/validate-python.sh

workflows:
	bash scripts/ci/validate-workflows.sh

modbus-contracts:
	bash scripts/ci/validate-modbus-contracts.sh

terraform:
	bash scripts/ci/validate-terraform.sh

docker:
	bash scripts/ci/validate-docker.sh

aws-preflight:
	bash scripts/aws/preflight-audit.sh

aws-state-bootstrap-validate:
	bash scripts/aws/validate-state-bootstrap.sh

aws-foundation-bootstrap-validate:
	bash scripts/aws/validate-foundation-deployment-bootstrap.sh

aws-github-oidc-bootstrap-validate:
	bash scripts/aws/validate-github-oidc-bootstrap.sh

aws-image-evidence-bootstrap-validate:
	bash scripts/aws/validate-github-image-evidence-bootstrap.sh

stack-up:
	bash scripts/dev/local-stack.sh up

stack-modbus-up:
	bash scripts/dev/local-stack.sh modbus-up

stack-live-up:
	bash scripts/dev/local-stack.sh live-up

stack-naive-up:
	bash scripts/dev/local-stack.sh naive-up

stack-stealthy-up:
	bash scripts/dev/local-stack.sh stealthy-up

stack-down:
	bash scripts/dev/local-stack.sh down

stack-reset:
	bash scripts/dev/local-stack.sh reset

stack-logs:
	bash scripts/dev/local-stack.sh logs

stack-ps:
	bash scripts/dev/local-stack.sh ps

stack-smoke:
	bash scripts/dev/local-stack.sh smoke

stack-modbus-smoke:
	bash scripts/dev/local-stack.sh modbus-smoke

stack-live-smoke:
	bash scripts/dev/local-stack.sh live-smoke

stack-attack-smoke:
	bash scripts/dev/local-stack.sh attack-smoke

stack-naive-smoke:
	bash scripts/dev/local-stack.sh naive-smoke

stack-stealthy-smoke:
	bash scripts/dev/local-stack.sh stealthy-smoke

stack-dashboard-smoke:
	bash scripts/dev/local-stack.sh dashboard-smoke
