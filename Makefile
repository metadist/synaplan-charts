# Synaplan Charts Makefile

# Dynamically discover all charts in charts/ directory
CHARTS := $(patsubst charts/%,%,$(wildcard charts/*))

.PHONY: all docs lint package clean

all: docs lint package ## Generate docs, lint, and package charts (default)

.PHONY: docs
docs: ## Generate documentation with helm-docs
	@command -v helm-docs >/dev/null 2>&1 || { echo "helm-docs not installed. Install from https://github.com/norwoodj/helm-docs"; exit 1; }
	@echo "Generating documentation..."
	@helm-docs

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
		if [ -f "ci/$$chart/lint-values.yaml" ]; then \
			helm template charts/$$chart -f ci/$$chart/lint-values.yaml > /tmp/$$chart-templated.yaml; \
		else \
			helm template charts/$$chart > /tmp/$$chart-templated.yaml; \
		fi; \
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

.PHONY: clean
clean: ## Remove build artifacts
	@echo "Cleaning build artifacts..."
	@rm -rf dist/
	@rm -f /tmp/*-templated.yaml

.PHONY: install-helm-docs
install-helm-docs: ## Install helm-docs tool
	@echo "Installing helm-docs..."
	@cd /tmp && \
	wget https://github.com/norwoodj/helm-docs/releases/download/v1.13.1/helm-docs_1.13.1_Linux_x86_64.tar.gz && \
	tar -xzf helm-docs_1.13.1_Linux_x86_64.tar.gz && \
	sudo mv helm-docs /usr/local/bin/ && \
	rm helm-docs_1.13.1_Linux_x86_64.tar.gz

.PHONY: install-kubeconform
install-kubeconform: ## Install kubeconform tool
	@echo "Installing kubeconform..."
	@cd /tmp && \
	curl -L https://github.com/yannh/kubeconform/releases/latest/download/kubeconform-linux-amd64.tar.gz | tar xz && \
	sudo mv kubeconform /usr/local/bin/

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
