# mayfly — developer entrypoints.
#
# `make lint` is the gate that has to stay green. It exists because the
# monitoring chart shipped in a state where `helm template` failed outright,
# and nothing in the repo would have caught that.

SHELL := /bin/bash
.DEFAULT_GOAL := help

# A throwaway registry value: the chart requires image.repository to be set,
# and rendering is all we are checking here.
LINT_IMAGE_REPO ?= localhost/flask-app

.PHONY: help
help: ## Show this help
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

.PHONY: deps
deps: ## Fetch Helm chart dependencies
	helm dependency build charts/monitoring

.PHONY: lint
lint: lint-secrets lint-helm lint-tf ## Run every check

.PHONY: lint-helm
lint-helm: ## Lint and render both Helm charts
	@echo "==> helm lint"
	helm lint charts/flask-app --set image.repository=$(LINT_IMAGE_REPO)
	helm lint charts/monitoring
	@echo "==> helm template (catches unescaped {{ }} and broken values)"
	helm template flask-app charts/flask-app \
		--set image.repository=$(LINT_IMAGE_REPO) >/dev/null
	helm template monitoring charts/monitoring >/dev/null
	@echo "==> helm template with the HPA disabled"
	helm template flask-app charts/flask-app \
		--set image.repository=$(LINT_IMAGE_REPO) --set hpa.enabled=false >/dev/null
	@echo "OK"

.PHONY: lint-tf
lint-tf: ## Check Terraform formatting and lint rules
	@echo "==> terraform fmt"
	terraform fmt -check -recursive infra/
	@echo "==> tflint"
	cd infra && tflint --recursive --format compact
	@echo "OK"

# Scans through git rather than the filesystem. A directory scan also reads
# downloaded dependencies -- .terraform/ modules, vendored subcharts -- which
# are gitignored, cannot be committed, and are full of example ARNs. Driving
# the scan through git means the ignore rules live in .gitignore only.
.PHONY: lint-secrets
lint-secrets: ## Scan git history and staged changes for secrets and AWS account ids
	@echo "==> gitleaks (history)"
	gitleaks git --config .gitleaks.toml --no-banner --redact
	@echo "==> gitleaks (staged)"
	gitleaks git --staged --config .gitleaks.toml --no-banner --redact
	@echo "OK"

.PHONY: hooks
hooks: ## Install the pre-commit hook that scans staged changes
	@printf '#!/bin/sh\nexec gitleaks git --staged --config .gitleaks.toml --no-banner --redact\n' > .git/hooks/pre-commit
	@chmod +x .git/hooks/pre-commit
	@echo "installed .git/hooks/pre-commit"
