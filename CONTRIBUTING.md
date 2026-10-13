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
   make lint       # helm lint
   make validate   # template + kubeconform
   make check      # helm-unittest suites; renders the examples and the full-stack Helmfile
   make docs       # helm-docs; commit the result when a chart value changed
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

**Tags are the source of truth for chart `version`.** CI writes that field during release. It does not change `appVersion`.

Tags must follow the format: `{chart-name}-v{version}`

```bash
# For synaplan v0.2.0
git tag synaplan-v0.2.0
git push origin synaplan-v0.2.0

# For triton v0.2.0
git tag triton-v0.2.0
git push origin triton-v0.2.0

# For stt v0.1.0
git tag stt-v0.1.0
git push origin stt-v0.1.0
```

For the `stt` chart, `version`, `appVersion` and the image pins are separate:

- `version` is the chart release. CI sets it from the `stt-v*` tag. Do not
  edit it by hand for a release.
- `appVersion` is the image version. CI does **not** change it.
- `cudaImage` and `cpuImage` in `values.yaml` carry the `tag@digest` the
  pods pull.

Renovate raises both image pins when a new image version is published. Set
`appVersion` to that version in the same pull request.

A chart-only fix can ship as `stt-v0.1.1` while `appVersion` stays `0.1.0`.

### Automated Release

Once the tag is pushed:

1. **CI Pipeline Runs**
   - Lints all charts
   - Templates and validates manifests
   - Checks documentation is up-to-date
   - Runs deployment tests (placeholder for now)

2. **Release Job**
   - Extracts version from tag (`synaplan-v1.0.0` → version `1.0.0`)
   - Updates `Chart.yaml` `version` from the tag (tag is source of truth; `appVersion` stays as committed)
   - Packages the chart with correct version
   - Pushes to GHCR: `ghcr.io/metadist/synaplan-charts/{chart-name}`

3. **Quality Gate**
   - Verifies all jobs succeeded
   - Fails if any check or release step failed

### Version Management

**The git tag is the source of truth for chart `version`.** CI writes that field during release. It does not change `appVersion`. For `stt`, `appVersion` is the image version and is updated in the pull request that ships a new image (see above).

**Workflow:**
1. Create a tag with the desired chart version: `git tag synaplan-v1.0.0`
2. Push the tag: `git push origin synaplan-v1.0.0`
3. CI writes `version: 1.0.0` into `Chart.yaml` and releases

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

- Add test values to `ci/{chart-name}/lint-values.yaml`; further `lint-values-*.yaml` files in that directory are templated too
- Ensure charts pass `helm lint`
- Chart behaviour (a value produces this env entry, this input fails the render) goes into a helm-unittest suite under `charts/{chart-name}/tests/`
- Validate with kubeconform
- Test deployment examples locally

## Questions?

Open an issue or discussion on GitHub!
