# Contributing to Synaplan Charts

Thank you for your interest in contributing to Synaplan Charts!

## Development Workflow

1. **Fork and Clone**
   ```bash
   git clone https://github.com/metadist/synaplan-charts.git
   cd synaplan-charts
   ```

2. **Create a Branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

3. **Make Changes**
   - Update chart templates, values, or documentation
   - Follow Helm best practices
   - Test your changes locally

4. **Test Locally**
   ```bash
   # Lint charts
   make lint
   
   # Validate against Kubernetes API
   make validate
   
   # Generate documentation
   make docs
   
   # Package charts
   make package
   ```

5. **Commit and Push**
   ```bash
   git add .
   git commit -m "feat: add new feature"
   git push origin feature/your-feature-name
   ```

6. **Create Pull Request**
   - Create a PR against the `main` branch
   - Describe your changes
   - Link any related issues

## Release Process

Releases are automated via GitHub Actions and triggered by git tags.

### Create Release Tag

**Tags are the source of truth for versions.** The CI will automatically update `Chart.yaml` during release.

Tags must follow the format: `{chart-name}-v{version}`

```bash
# For synaplan v0.2.0
git tag synaplan-v0.2.0
git push origin synaplan-v0.2.0

# For triton v0.2.0
git tag triton-v0.2.0
git push origin triton-v0.2.0
```

**That's it!** No need to manually update Chart.yaml or worry about version mismatches.

### Automated Release

Once the tag is pushed:

1. **CI Pipeline Runs**
   - Lints all charts
   - Templates and validates manifests
   - Checks documentation is up-to-date
   - Runs deployment tests (placeholder for now)

2. **Release Job**
   - Extracts version from tag (`synaplan-v1.0.0` → version `1.0.0`)
   - Updates `Chart.yaml` with the tag version (tag is source of truth)
   - Packages the chart with correct version
   - Pushes to GHCR: `ghcr.io/metadist/synaplan-charts/{chart-name}`

3. **Quality Gate**
   - Verifies all jobs succeeded
   - Fails if any check or release step failed

### Version Management

**The git tag is the source of truth.** You don't need to update `Chart.yaml` manually - CI does it automatically during release.

**Workflow:**
1. Create a tag with the desired version: `git tag synaplan-v1.0.0`
2. Push the tag: `git push origin synaplan-v1.0.0`
3. CI automatically updates `Chart.yaml` to version `1.0.0` and releases

## Versioning Strategy

We follow [Semantic Versioning](https://semver.org/):

- **MAJOR** (1.0.0): Incompatible API changes
- **MINOR** (0.1.0): Backwards-compatible functionality additions
- **PATCH** (0.0.1): Backwards-compatible bug fixes

### Development Builds

Every push to the `main` branch automatically publishes development builds to GHCR:

- **Version format**: `0.0.0-dev.<commit-hash>` (e.g., `0.0.0-dev.abc1234`)
- **Purpose**: Testing unreleased features before creating a stable release
- **Not for production**: Development builds are ephemeral and may contain breaking changes

Example:
```bash
# Install a development build for testing
helm install synaplan oci://ghcr.io/metadist/synaplan-charts/synaplan --version 0.0.0-dev.abc1234
```

## Chart Guidelines

### Helm Best Practices

- Use `_helpers.tpl` for template functions
- Always include `.helmignore`
- Document all values in `values.yaml` with comments
- Use `README.md.gotmpl` for helm-docs generation
- Include examples in `ci/` directory

### Documentation

- Run `make docs` after changing values
- Update `README.md.gotmpl` for chart-specific docs
- Include usage examples

### Testing

- Add test values to `ci/{chart-name}/lint-values.yaml`
- Ensure charts pass `helm lint`
- Validate with kubeconform
- Test deployment examples locally

## Questions?

Open an issue or discussion on GitHub!
