# Agent Instructions

This file contains instructions for AI coding agents working on this repository.

## Before Committing Changes

**ALWAYS** run the following checks before creating a commit:

### 1. Generate Documentation

If you modified any chart files (values.yaml, templates, Chart.yaml, or README.md.gotmpl), regenerate the documentation:

```bash
make docs
```

This ensures the README.md files are up-to-date with any changes to values.yaml or templates.

### 2. Lint Charts

Verify all charts pass linting:

```bash
make lint
```

### 3. Validate Templates

Ensure all charts can be templated successfully:

```bash
make template
```

### 4. Run All Checks

To run all checks at once (docs, lint, package):

```bash
make all
```

## Important Notes

- **Documentation is auto-generated**: Never manually edit `charts/*/README.md` files. Always edit `charts/*/README.md.gotmpl` templates instead.
- **helm-docs version**: This project uses helm-docs v1.14.2 with `--skip-version-footer` flag. The version footer is disabled in templates.
- **Model names are immutable**: DO NOT change the names of deployed models (mistral-7b-instruct-v0.3, mistral-streaming, mistral-cpu).
- **Environments**: `deployments/synaplan-with-triton/environments/default` is the only environment committed here. A real cluster passes its own values file (`SYNAPLAN_VALUES_FILE`). Do not commit that file, and do not add a `prod` or `dev` environment to this repo.

## CI Pipeline

The CI pipeline will fail if:
- Documentation is out of date (helm-docs check)
- Charts fail linting
- Templates don't render
- Kubernetes manifests don't validate

Always run `make all` locally before pushing to avoid CI failures.
