.PHONY: ci docs python terraform docker hygiene

ci:
	bash scripts/ci/all.sh

hygiene:
	bash scripts/ci/validate-repo-hygiene.sh

docs:
	bash scripts/ci/validate-docs.sh

python:
	bash scripts/ci/validate-python.sh

terraform:
	bash scripts/ci/validate-terraform.sh

docker:
	bash scripts/ci/validate-docker.sh
