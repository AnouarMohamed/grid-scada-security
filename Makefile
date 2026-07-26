.PHONY: ci docs python modbus-contracts terraform docker hygiene stack-up stack-modbus-up stack-down stack-reset stack-logs stack-ps stack-smoke stack-modbus-smoke stack-dashboard-smoke

ci:
	bash scripts/ci/all.sh

hygiene:
	bash scripts/ci/validate-repo-hygiene.sh

docs:
	bash scripts/ci/validate-docs.sh

python:
	bash scripts/ci/validate-python.sh

modbus-contracts:
	bash scripts/ci/validate-modbus-contracts.sh

terraform:
	bash scripts/ci/validate-terraform.sh

docker:
	bash scripts/ci/validate-docker.sh

stack-up:
	bash scripts/dev/local-stack.sh up

stack-modbus-up:
	bash scripts/dev/local-stack.sh modbus-up

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

stack-dashboard-smoke:
	bash scripts/dev/local-stack.sh dashboard-smoke
