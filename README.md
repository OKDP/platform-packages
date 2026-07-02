[![ci](https://github.com/okdp/platform-packages/actions/workflows/ci.yml/badge.svg)](https://github.com/okdp/platform-packages/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/okdp/platform-packages)](https://github.com/okdp/platform-packages/releases/latest)&ensp;&ensp;
[![KuboCD](https://img.shields.io/badge/kubocd-v0.2.2-green.svg)](https://github.com/kubocd/kubocd)&ensp;&ensp;
[![Kubernetes](https://img.shields.io/badge/kubernetes-1.28+-blue.svg)](https://kubernetes.io/)&ensp;&ensp;
[![License Apache2](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](http://www.apache.org/licenses/LICENSE-2.0)
<a href="https://okdp.io">
<img src="https://okdp.io/logos/okdp-notext.svg" height="20px" style="margin: 0 2px;" />
</a>

## Overview

This repository builds and publishes the OKDP platform packages used to operate platform services with [KuboCD](https://www.kubocd.io/).

It is **packages-only**: it owns the package definitions under `packages/` and the CI that builds and publishes them as OCI artifacts. It does **not** own the deployment layer (releases, contexts, Flux/KuboCD bootstrap). Deployment lives in [`OKDP/okdp-sandbox`](https://github.com/OKDP/okdp-sandbox), which consumes the packages published here.

## KuboCD Concepts

- **Package**: a versioned OCI artifact that bundles a KuboCD application descriptor and one or more Helm charts. The manifests under `packages/` define the packages published by this repository.

Packages are deployed through KuboCD **Releases** that reference layered **Contexts**. Those deployment resources are maintained in [`OKDP/okdp-sandbox`](https://github.com/OKDP/okdp-sandbox), not here.

## Structure

```
packages/
├── system/             # Infrastructure & system packages
│   ├── cert-manager/
│   ├── ingress-nginx/
│   ├── dns-server/
│   └── ...
└── services/           # Services
    ├── superset/
    ├── jupyterhub/
    ├── seaweedfs/
    └── ...
platform-packages-values.yaml   # OCI publish target (packageRepository), the source of truth used by CI
```

Key paths:

- [`packages/system`](./packages/system): infrastructure and platform foundation packages.
- [`packages/services`](./packages/services): data and application service packages.
- [`platform-packages-values.yaml`](./platform-packages-values.yaml): the OCI repository packages are published to.

## Building Packages

The OCI repository packages are published to is defined once in [`platform-packages-values.yaml`](./platform-packages-values.yaml) (`packageRepository`). Use the same value for local builds.

### Basic Build Command

```bash
# Build a system package
kubocd package ./packages/system/cert-manager/cert-manager.yaml --ociRepoPrefix quay.io/okdp/platform-packages

# Build a service package
kubocd package ./packages/services/superset/superset.yaml --ociRepoPrefix quay.io/okdp/platform-packages
```

### Custom OCI Repository

```bash
# Using a different OCI registry
kubocd package ./packages/system/cert-manager/cert-manager.yaml --ociRepoPrefix myregistry.io/my-org/packages

# Using a different prefix for packages
kubocd package ./packages/services/jupyterhub/jupyterhub.yaml --ociRepoPrefix harbor.company.com/okdp-prod
```

### Examples

```bash
# Build all system packages
for pkg in packages/system/*/; do
  kubocd package "$pkg"*.yaml --ociRepoPrefix quay.io/okdp/platform-packages
done

# Build specific package
kubocd package ./packages/services/seaweedfs/seaweedfs.yaml --ociRepoPrefix quay.io/okdp/platform-packages
```

### Build Output

Packages are pushed to: `{ociRepoPrefix}/{package-name}:{tag}`

Example: `quay.io/okdp/platform-packages/superset:4.0.0-p02`

## GitHub CI and Publishing

The GitHub workflows share the reusable [`kubocd-package-template.yml`](./.github/workflows/kubocd-package-template.yml) workflow for both CI validation and publishing.

### CI Workflow

[`ci.yml`](./.github/workflows/ci.yml) runs on pushes, pull requests, and manual dispatch. It:

- reads the OCI package prefix from [`platform-packages-values.yaml`](./platform-packages-values.yaml);
- builds **every** package manifest under `packages/` that contains `modules:`;
- pushes CI test packages to the repository-scoped GitHub Container Registry path.

Building covers every package, so packaging errors are caught repo-wide. Deployment of the published packages (Flux/KuboCD bootstrap, contexts, releases) and its end-to-end validation live in [`OKDP/okdp-sandbox`](https://github.com/OKDP/okdp-sandbox), not here.

The KuboCD package CI job is skipped for fork pull requests because GitHub intentionally gives those runs a read-only token, which cannot push to GHCR.

### CI Registry

The `ci` workflow builds packages for CI validation and pushes them to the repository-scoped GitHub Container Registry path:

```text
ghcr.io/okdp/platform-packages/platform-packages/{package-name}:{tag}
```

### Release Publishing

Published release packages use the public repository from [`platform-packages-values.yaml`](./platform-packages-values.yaml):

```text
quay.io/okdp/platform-packages/{package-name}:{tag}
```

[`publish.yml`](./.github/workflows/publish.yml) can be dispatched manually and publishes packages to Quay using `REGISTRY_USERNAME` and `REGISTRY_ROBOT_TOKEN`. [`publish-on-merge.yml`](./.github/workflows/publish-on-merge.yml) triggers that publish workflow after a successful `ci` run on `main`, and [`release-please.yml`](./.github/workflows/release-please.yml) triggers it when Release Please creates a new release after a merged pull request.
