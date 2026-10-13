# Synaplan Charts Makefile

# Dynamically discover all charts in charts/ directory
CHARTS := $(patsubst charts/%,%,$(wildcard charts/*))

SHELL := bash
.SHELLFLAGS := -o pipefail -c

HELM ?= helm
HELMFILE := helmfile --helm-binary $(HELM) -f deployments/synaplan-with-triton/helmfile.yaml.gotmpl -e default

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
check: ## Unit-test the synaplan chart; render the examples and the full-stack Helmfile
	@$(HELM) unittest --help >/dev/null 2>&1 || { echo "helm-unittest not installed. Run 'make install-helm-unittest'"; exit 1; }
	@command -v helmfile >/dev/null 2>&1 || { echo "helmfile not installed. Run 'make install-helmfile'"; exit 1; }
	@command -v kubeconform >/dev/null 2>&1 || { echo "kubeconform not installed. Run 'make install-kubeconform'"; exit 1; }
	$(HELM) unittest charts/synaplan
	$(HELM) template charts/synaplan | kubeconform -strict -summary -
	$(HELM) template charts/synaplan -f examples/values-opendesk.yaml | kubeconform -strict -summary -
	$(HELM) template charts/synaplan -f examples/values-opendesk.yaml -f examples/values-managed-settings.yaml --set image.tag=5.1.0 | kubeconform -strict -summary -
	$(HELMFILE) --state-values-set services.triton.mode=gpu template >/dev/null
	$(HELMFILE) --state-values-set services.triton.mode=cpu template >/dev/null
	$(HELMFILE) --state-values-set services.triton.mode=remote template >/dev/null
	$(HELMFILE) --state-values-set services.synaplan.values.features.registration=false -l name=synaplan template | kubeconform -strict -summary -

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
