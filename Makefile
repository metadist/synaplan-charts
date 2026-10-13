# Synaplan Charts Makefile

# Dynamically discover all charts in charts/ directory
CHARTS := $(patsubst charts/%,%,$(wildcard charts/*))

HELM ?= helm
HELMFILE := deployments/synaplan-with-triton/helmfile.yaml.gotmpl
# Overlays for the synaplan chart that validate renders next to its lint values
EXAMPLES := examples/values-airgap.yaml examples/values-opendesk.yaml

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
		helm lint charts/$$chart || exit 1; \
	done

.PHONY: template
template: ## Template charts for validation
	@echo "Templating and validating charts..."
	@for chart in $(CHARTS); do \
		echo "Templating charts/$$chart..."; \
		: > /tmp/$$chart-templated.yaml; \
		for values in ci/$$chart/lint-values*.yaml; do \
			if [ -f "$$values" ]; then \
				helm template charts/$$chart -f "$$values" >> /tmp/$$chart-templated.yaml || exit 1; \
			fi; \
		done; \
		if [ ! -s /tmp/$$chart-templated.yaml ]; then \
			helm template charts/$$chart > /tmp/$$chart-templated.yaml || exit 1; \
		fi; \
	done
	@for values in $(EXAMPLES); do \
		echo "Templating charts/synaplan with $$values..."; \
		helm template charts/synaplan -f "$$values" >> /tmp/synaplan-templated.yaml || exit 1; \
	done

.PHONY: package
package: ## Package all charts to dist/
	@echo "Packaging charts..."
	@mkdir -p dist
	@for chart in $(CHARTS); do \
		echo "Packaging charts/$$chart..."; \
		helm package charts/$$chart -d dist || exit 1; \
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
check: ## Unit-test the synaplan chart and render the full-stack Helmfile
	@$(HELM) unittest --help >/dev/null 2>&1 || { echo "helm-unittest not installed. Run 'make install-helm-unittest'"; exit 1; }
	@command -v helmfile >/dev/null 2>&1 || { echo "helmfile not installed"; exit 1; }
	$(HELM) unittest charts/synaplan
	@for values in "" ci/full-stack-cpu.yaml ci/full-stack-remote.yaml; do \
		echo "helmfile template $${values:-(default environment)}"; \
		helmfile --helm-binary $(HELM) -f $(HELMFILE) -e default $${values:+--state-values-file $(CURDIR)/$$values} template >/dev/null || exit 1; \
	done

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
	$(HELM) plugin install https://github.com/helm-unittest/helm-unittest --version v1.2.1

.PHONY: install-kubeconform
install-kubeconform: ## Install kubeconform tool
	@echo "Installing kubeconform..."
	@cd /tmp && \
	curl -L https://github.com/yannh/kubeconform/releases/latest/download/kubeconform-linux-amd64.tar.gz | tar xz && \
	sudo mv kubeconform /usr/local/bin/

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
