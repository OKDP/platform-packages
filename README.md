[![ci](https://github.com/okdp/platform-packages/actions/workflows/ci.yml/badge.svg)](https://github.com/okdp/platform-packages/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/okdp/platform-packages)](https://github.com/okdp/platform-packages/releases/latest)&ensp;&ensp;
[![Flux](https://img.shields.io/badge/flux-latest-purple.svg)](https://fluxcd.io/)
[![KuboCD](https://img.shields.io/badge/kubocd-v0.2.1-green.svg)](https://github.com/kubocd/kubocd)&ensp;&ensp;
[![Kubernetes](https://img.shields.io/badge/kubernetes-1.28+-blue.svg)](https://kubernetes.io/)
[![Kind](https://img.shields.io/badge/kind-latest-orange.svg)](https://kind.sigs.k8s.io/)&ensp;&ensp;
[![License Apache2](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](http://www.apache.org/licenses/LICENSE-2.0)
<a href="https://okdp.io">
<img src="https://okdp.io/logos/okdp-notext.svg" height="20px" style="margin: 0 2px;" />
</a>

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
```

## Building Packages

### Basic Build Command

```bash
# Build a system package
kubocd pack --ociRepoPrefix quay.io/okdp/platform-packages-v0.3 ./packages/system/cert-manager/cert-manager.yaml

# Build an OKDP package
kubocd pack --ociRepoPrefix quay.io/okdp/platform-packages-v0.3 ./packages/okdp-packages/superset/superset.yaml
```

### Custom OCI Repository

```bash
# Using a different OCI registry
kubocd pack --ociRepoPrefix myregistry.io/my-org/packages-v0.1 ./packages/system/cert-manager/cert-manager.yaml

# Using a different prefix for packages
kubocd pack --ociRepoPrefix harbor.company.com/okdp-prod ./packages/okdp-packages/jupyterhub/jupyterhub.yaml
```

### Examples

```bash
# Build all system packages
for pkg in packages/system/*/; do
  kubocd pack --ociRepoPrefix quay.io/okdp/platform-packages-v0.3 "$pkg"*.yaml
done

# Build specific package
kubocd pack --ociRepoPrefix quay.io/okdp/platform-packages-v0.3 ./packages/okdp-packages/seaweedfs/seaweedfs.yaml
```

### Build Output

Packages are pushed to: `{ociRepoPrefix}/{package-name}:{tag}`

Example: `quay.io/okdp/platform-packages-v0.3/superset:4.0.0-p02` 