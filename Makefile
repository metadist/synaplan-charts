# Synaplan Charts Makefile

# Dynamically discover all charts in charts/ directory
CHARTS := $(patsubst charts/%,%,$(wildcard charts/*))

SHELL := bash
.SHELLFLAGS := -o pipefail -c

HELM ?= helm
HELMFILE := helmfile --helm-binary $(HELM)

.PHONY: all docs lint package clean

all: docs lint validate check package ## Generate docs, lint, validate, check and package charts (default)

.PHONY: docs
docs: ## Generate documentation with helm-docs
	@command -v helm-docs >/dev/null 2>&1 || { echo "helm-docs not installed. Install from https://github.com/norwoodj/helm-docs"; exit 1; }
	@echo "Generating documentation..."
	@helm-docs --skip-version-footer

.PHONY: lint
lint: ## Lint all charts
	@echo "Linting charts..."
	@for chart in $(CHARTS); do \
		echo "Linting charts/$$chart..."; \
		$(HELM) lint charts/$$chart || exit 1; \
	done

.PHONY: template
template: ## Template charts for validation
	@echo "Templating and validating charts..."
	@for chart in $(CHARTS); do \
		echo "Templating charts/$$chart..."; \
		: > /tmp/$$chart-templated.yaml; \
		for values in ci/$$chart/lint-values*.yaml; do \
			if [ -f "$$values" ]; then \
				$(HELM) template charts/$$chart -f "$$values" >> /tmp/$$chart-templated.yaml || exit 1; \
			fi; \
		done; \
		if [ ! -s /tmp/$$chart-templated.yaml ]; then \
			$(HELM) template charts/$$chart > /tmp/$$chart-templated.yaml || exit 1; \
		fi; \
	done

.PHONY: package
package: ## Package all charts to dist/
	@echo "Packaging charts..."
	@mkdir -p dist
	@for chart in $(CHARTS); do \
		echo "Packaging charts/$$chart..."; \
		$(HELM) package charts/$$chart -d dist || exit 1; \
	done
	@echo "Charts packaged in dist/"

.PHONY: validate
validate: template ## Validate charts with kubeconform
	@command -v kubeconform >/dev/null 2>&1 || { echo "kubeconform not installed. Run 'make install-kubeconform'"; exit 1; }
	@echo "Validating Kubernetes manifests..."
	@for chart in $(CHARTS); do \
		echo "Validating charts/$$chart..."; \
		kubeconform -strict -summary /tmp/$$chart-templated.yaml || exit 1; \
	done

.PHONY: check
check: ## Unit-test the synaplan chart; render the Helmfile
	@$(HELM) unittest --help >/dev/null 2>&1 || { echo "helm-unittest not installed. Run 'make install-helm-unittest'"; exit 1; }
	@command -v helmfile >/dev/null 2>&1 || { echo "helmfile not installed. Run 'make install-helmfile'"; exit 1; }
	@command -v kubeconform >/dev/null 2>&1 || { echo "kubeconform not installed. Run 'make install-kubeconform'"; exit 1; }
	$(HELM) unittest charts/synaplan
	$(HELM) template charts/synaplan --set appSecret=check,database.password=check | kubeconform -strict -summary -
	MASTER_PASSWORD=check $(HELMFILE) -e standalone template | kubeconform -strict -summary -
	MASTER_PASSWORD=check $(HELMFILE) -e standalone --state-values-set apps.triton.enabled=true,technical.triton.mode=cpu template | kubeconform -strict -summary -
	MASTER_PASSWORD=check $(HELMFILE) -e opendesk template | kubeconform -strict -summary -
	(MASTER_PASSWORD=check $(HELMFILE) -e standalone --state-values-set apps.ollama.enabled=false template 2>&1 || true) | grep -q 'no model backend'
	($(HELMFILE) -e standalone -l name=synaplan template 2>&1 || true) | grep -q 'appSecret is empty'
	MASTER_PASSWORD=check $(HELMFILE) -e standalone -l name=synaplan template | grep -q 'name: BOOTSTRAP_ADMIN_EMAIL'
	MASTER_PASSWORD=check $(HELMFILE) -e opendesk --state-values-set technical.synaplan.oidc.accessPolicy.orgCode=org_1,technical.synaplan.oidc.accessPolicy.allowUserProvisioning=false,technical.synaplan.oidc.scopes=openid -l name=synaplan template | grep -A1 -E 'name: OIDC_(ORG_CODE|ALLOW_USER_PROVISIONING|SCOPES)$$' | grep -c -E 'value: "(org_1|false|openid)"' | grep -qx 9
	MASTER_PASSWORD=check $(HELMFILE) -e standalone --state-values-set certificate.wildcard=true,ingress.tls.secretName=wildcard-tls -l name=synaplan template | (! grep -q 'cert-manager.io/')
	MASTER_PASSWORD=check $(HELMFILE) -e standalone --state-values-set customization.release.synaplan.lint=../../../ci/synaplan/lint-values.yaml -l name=synaplan template | grep -q 'image: "ghcr.io/metadist/synaplan:latest"'

.PHONY: clean
clean: ## Remove build artifacts
	@echo "Cleaning build artifacts..."
	@rm -rf dist/
	@rm -f /tmp/*-templated.yaml

.PHONY: install-helm-docs
install-helm-docs: ## Install helm-docs tool
	@echo "Installing helm-docs..."
	@cd /tmp && \
	wget https://github.com/norwoodj/helm-docs/releases/download/v1.14.2/helm-docs_1.14.2_Linux_x86_64.tar.gz && \
	tar -xzf helm-docs_1.14.2_Linux_x86_64.tar.gz && \
	sudo mv helm-docs /usr/local/bin/ && \
	rm helm-docs_1.14.2_Linux_x86_64.tar.gz

.PHONY: install-helm-unittest
install-helm-unittest: ## Install the helm-unittest plugin
	@echo "Installing helm-unittest..."
	@# v1.0.3 is the last release whose plugin.yaml Helm 3.14 (pinned in CI) can load.
	@$(HELM) plugin install https://github.com/helm-unittest/helm-unittest --version v1.0.3

.PHONY: install-helmfile
install-helmfile: ## Install helmfile
	@echo "Installing helmfile..."
	@cd /tmp && \
	curl -fsSL -o helmfile.tar.gz https://github.com/helmfile/helmfile/releases/download/v1.6.0/helmfile_1.6.0_linux_amd64.tar.gz && \
	tar -xzf helmfile.tar.gz helmfile && \
	sudo mv helmfile /usr/local/bin/ && \
	rm helmfile.tar.gz

.PHONY: install-kubeconform
install-kubeconform: ## Install kubeconform tool
	@echo "Installing kubeconform..."
	@cd /tmp && \
	curl -L https://github.com/yannh/kubeconform/releases/latest/download/kubeconform-linux-amd64.tar.gz | tar xz && \
	sudo mv kubeconform /usr/local/bin/

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
