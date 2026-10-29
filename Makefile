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

VENV := .venv

# --- Local demo on kind -------------------------------------------------------

KIND_CLUSTER ?= mayfly
# The git revision Argo CD deploys. Argo CD pulls from GitHub, so a branch has
# to be pushed before `make demo REVISION=<branch>` can deploy it.
REVISION ?= master
DEMO_IMAGE := mayfly/flask-app:dev

ARGOCD_CHART_VERSION := 10.11.6
METRICS_SERVER_CHART_VERSION := 3.14.0

# Every cluster command names the kind context explicitly, so the demo cannot
# land on whatever cluster the shell happens to point at -- EKS included.
KUBECTL := kubectl --context kind-$(KIND_CLUSTER)
HELM := helm --kube-context kind-$(KIND_CLUSTER)

.PHONY: help
help: ## Show this help
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

.PHONY: deps
deps: ## Fetch Helm chart dependencies
	helm dependency build charts/monitoring

.PHONY: demo
demo: demo-tools demo-cluster demo-image demo-bootstrap demo-wait ## Stand up the whole platform on a local kind cluster
	@echo
	@echo "mayfly is up on kind-$(KIND_CLUSTER) (revision: $(REVISION))."
	@echo "  make ui        port-forward Argo CD, Grafana and the app"
	@echo "  make destroy   delete the cluster"

.PHONY: demo-tools
demo-tools:
	@for t in docker kind kubectl helm openssl; do \
		command -v $$t >/dev/null || { echo "missing: $$t (see README, Run locally)"; exit 1; }; \
	done
	@docker info >/dev/null 2>&1 || { echo "docker is installed but the engine is not running"; exit 1; }

# Idempotent: re-running `make demo` reuses the cluster.
.PHONY: demo-cluster
demo-cluster:
	@kind get clusters 2>/dev/null | grep -qx '$(KIND_CLUSTER)' \
		|| kind create cluster --name $(KIND_CLUSTER) --config deploy/kind/cluster.yaml

.PHONY: demo-image
demo-image:
	docker build --tag $(DEMO_IMAGE) app/
	kind load docker-image $(DEMO_IMAGE) --name $(KIND_CLUSTER)

# Installs what Argo CD itself cannot: Argo CD, the metrics-server the HPA
# needs, and the Grafana admin secret that must never be in git. The password
# is generated once and kept across re-runs.
.PHONY: demo-bootstrap
demo-bootstrap:
	$(HELM) upgrade --install metrics-server metrics-server \
		--repo https://kubernetes-sigs.github.io/metrics-server/ \
		--version $(METRICS_SERVER_CHART_VERSION) --namespace kube-system \
		--set 'args={--kubelet-insecure-tls}' --wait
	$(HELM) upgrade --install argocd argo-cd \
		--repo https://argoproj.github.io/argo-helm \
		--version $(ARGOCD_CHART_VERSION) --namespace argocd --create-namespace \
		--values deploy/kind/argocd-values.yaml --wait
	$(KUBECTL) create namespace monitoring --dry-run=client -o yaml | $(KUBECTL) apply -f -
	@$(KUBECTL) -n monitoring get secret grafana-admin-secret >/dev/null 2>&1 \
		|| $(KUBECTL) -n monitoring create secret generic grafana-admin-secret \
			--from-literal=admin-user=admin \
			--from-literal=admin-password="$$(openssl rand -base64 24)"
	sed 's|@REVISION@|$(REVISION)|g' deploy/kind/root-app.yaml | $(KUBECTL) apply -f -

# The child Applications only exist once root-app has synced, so wait for
# them to appear before waiting on their status. Ten minutes covers a cold
# image cache; a warm re-run takes seconds.
.PHONY: demo-wait
demo-wait:
	@echo "==> waiting for Argo CD to sync monitoring and flask-app"
	@deadline=$$(( $$(date +%s) + 600 )); \
	for app in monitoring flask-app; do \
		until [ "$$($(KUBECTL) -n argocd get application $$app \
				-o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null)" = "Synced/Healthy" ]; do \
			if [ $$(date +%s) -ge $$deadline ]; then \
				echo "timed out; current state:"; $(KUBECTL) -n argocd get applications; exit 1; \
			fi; \
			sleep 5; \
		done; \
		echo "    $$app: Synced/Healthy"; \
	done

.PHONY: ui
ui: ## Port-forward Argo CD (8080), Grafana (3000) and the app (8081); Ctrl-C to stop
	@echo "Argo CD  http://localhost:8080  admin / $$($(KUBECTL) -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
	@echo "Grafana  http://localhost:3000  admin / $$($(KUBECTL) -n monitoring get secret grafana-admin-secret -o jsonpath='{.data.admin-password}' | base64 -d)"
	@echo "App      http://localhost:8081"
	@trap 'kill 0' INT TERM; \
	$(KUBECTL) -n argocd port-forward svc/argocd-server 8080:80 >/dev/null & \
	$(KUBECTL) -n monitoring port-forward svc/monitoring-grafana 3000:80 >/dev/null & \
	$(KUBECTL) -n flask-app port-forward svc/flask-app 8081:8080 >/dev/null & \
	wait

.PHONY: destroy
destroy: ## Delete the local kind cluster (never touches AWS)
	kind delete cluster --name $(KIND_CLUSTER)

.PHONY: lint
lint: lint-secrets lint-python lint-helm lint-tf ## Run every check

# Creates .venv on first use so a fresh clone can run `make lint` unaided.
# flake8 and pytest only ever ran in CI, and CI only ran on master -- which is
# how two lint violations sat on master for months.
$(VENV)/bin/flake8:
	python3 -m venv $(VENV)
	$(VENV)/bin/pip -q install -r app/requirements-dev.txt

.PHONY: lint-python
lint-python: $(VENV)/bin/flake8 ## Lint and test the Flask app
	@echo "==> flake8"
	$(VENV)/bin/flake8 app/src app/tests --max-line-length=100
	@echo "==> pytest"
	cd app && ../$(VENV)/bin/pytest tests/ -q --cov=src --cov-fail-under=80
	@echo "OK"

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
	@echo "==> helm template with the kind values (make demo)"
	helm template flask-app charts/flask-app --values charts/flask-app/values-kind.yaml >/dev/null
	helm template monitoring charts/monitoring --values charts/monitoring/values-kind.yaml >/dev/null
	helm lint deploy/kind/apps
	helm template kind-apps deploy/kind/apps >/dev/null
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
