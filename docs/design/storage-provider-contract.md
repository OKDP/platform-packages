# Storage Provider Contract

> **Status:** canonical specification·
>
> **Companion ADR:** [`adr/0001-storage-provider-abstraction.md`](../adr/0001-storage-provider-abstraction.md)
>
> The ADR explains **why** the abstraction exists (the decision, consequences, migration).
> This document specifies **how** the contract works and how to implement a provider.

## Purpose

This document defines the contract between **storage consumers** (Trino, Hive Metastore, Spark
History, JupyterHub, Polaris, …) and **storage providers** (SeaweedFS, RustFS, MinIO, Ceph RGW,
AWS S3, …) in OKDP.

Consumers depend only on this backend-neutral contract. Each provider translates the same contract
into its own native resources. Switching backend must change only the provider, never a consumer.

The guiding principle: **the contract represents what consumers need, not how providers implement
it.** Keep it as small and stable as possible — every field is a commitment every future provider
must honour.

---

## Architecture

```
   Trino   Hive Metastore   Spark History   JupyterHub   Polaris        (consumers)
     └──────────┴───────────────┴──────────────┴────────────┘
                                │  depend only on
                                ▼
                   ┌─────────────────────────┐
                   │  defaultStorage contract │      (the stable Target interface)
                   │   provider · buckets ·   │
                   │          grants          │
                   └─────────────────────────┘
                                ▲  implement (translate to native)
     ┌──────────┬───────────────┬──────────────┬────────────┬──────────┐
  SeaweedFS   RustFS          MinIO          Ceph RGW      AWS S3      ...   (providers/adapters)
```

This is the **Adapter pattern**: consumers are the *clients*, `defaultStorage` is the *target
interface*, each provider package is an *adapter* to a concrete backend (*adaptee*).

**The core invariant:** a provider reads **only** the contract. It must never reference a consumer
context (`.Context.trino`, `.Context.hiveMetastore`, …). Consumers publish their needs into the
contract; the provider consumes them without knowing which service a grant belongs to.

---

## Responsibilities

### Consumers MUST

- consume only `defaultStorage.provider` (endpoints, region, capabilities, `sts.roleArn`);
- reference their own S3 credentials through a Kubernetes Secret, and declare a matching **grant**
  (same secret) describing the buckets and actions they need;
- **template** provider capabilities (`pathStyle`, `tls`, `region`) instead of hardcoding them;
- never provision buckets, users, roles or policies;
- never reference backend-specific configuration.

### Providers MUST

- publish `defaultStorage.provider` (endpoints + capabilities + `sts.roleArn`);
- realize the declared `buckets` and `grants` (see [Provisioning boundary](#provisioning-boundary)):
  create them for self-hosted backends, or validate/ignore for external ones;
- keep all backend-specific configuration inside **their own package schema** — never in the shared
  contract (see [What is *not* in the contract](#what-is-not-in-the-contract));
- never read a consumer context.

---

## The contract

Exposed under the `defaultStorage` context key. Its three parts are the **entire** shared contract:

```yaml
defaultStorage:

  # (1) provider — how consumers connect. Published by the provider, consumed by everyone.
  provider:
    type: s3                       # storage protocol (only s3 today)
    name: <provider name>          # informational (SeaweedFS, RustFS, AWS, …)
    region: <region>               # "dummy" for self-hosted, real region for AWS
    pathStyle: true|false          # path-style vs virtual-hosted addressing
    tls: true|false                # endpoints served over HTTPS
    endpoints:
      apiUrl: <s3 endpoint>        # required
      stsUrl: <sts endpoint>       # required only if any grant sets sts: true
      consoleUrl: <console url>    # optional (operator convenience)
    sts:
      roleArn: <role arn>          # provider OUTPUT; consumed by STS clients (Polaris)

  # (2) buckets — the buckets the platform requires. Declared once, backend-independent.
  buckets:
    - name: bronze
    - name: silver
    - name: gold
    - name: hive
      anonymousRead: true          # optional, default false
    - name: spark-events
      anonymousRead: true

  # (3) grants — neutral access requirements. Each grant is self-contained: no reference to
  #     any consumer context. The provider translates it to native identities/policies.
  grants:
    - principal: trino             # logical name (also the backend username)
      credentialsSecret:           # the SAME secret the consumer uses
        name: creds-trino-s3
        accessKeyKey: S3_ACCESS_KEY
        secretKeyKey: S3_SECRET_ACCESS
      buckets: ["*"]               # "*" = all buckets, or an explicit list
      actions: [read, write, list, admin]
    - principal: polaris
      credentialsSecret:
        name: creds-polaris-s3
        accessKeyKey: accessKey
        secretKeyKey: secretKey
      buckets: ["*"]
      actions: [read, write, list, admin]
      sts: true                    # this principal performs AssumeRole
```

---

## Field reference

### `provider`

| Field | Set by | Required | Meaning |
|---|---|---|---|
| `type` | provider | yes | Storage protocol. Only `s3` today. |
| `name` | provider | yes | Human-readable backend name (informational). |
| `region` | provider | yes | S3 region. `dummy` for self-hosted; a real region for AWS. Consumers template it. |
| `pathStyle` | provider | yes | `true` = path-style (`host/bucket`); `false` = virtual-hosted (`bucket.host`). Self-hosted → `true`; AWS → `false`. |
| `tls` | provider | yes | Endpoints served over HTTPS. |
| `endpoints.apiUrl` | provider | yes | S3 API endpoint. |
| `endpoints.stsUrl` | provider | conditional | STS endpoint. Required if any grant sets `sts: true`. May equal `apiUrl` (SeaweedFS/RustFS share it). |
| `endpoints.consoleUrl` | provider | no | Management console URL (operator convenience; consumers do not use it). |
| `sts.roleArn` | provider | conditional | Role ARN a consumer passes to `AssumeRole`. A **provider output** — see [STS model](#sts-and-authorization-model). Required if any grant sets `sts: true`. |

### `buckets`

| Field | Set by | Required | Meaning |
|---|---|---|---|
| `name` | platform | yes | Bucket name. |
| `anonymousRead` | platform | no (default `false`) | Grant public read on the bucket. Neutral (all S3 backends support a public-read policy). |

Buckets are declared once and are backend-independent. The provider ensures they exist (self-hosted)
or assumes they pre-exist (external). Listing every platform bucket here — rather than relying on a
backend's on-demand bucket creation — is required, because some backends (AWS S3, MinIO) do not
auto-create buckets.

### `grants`

| Field | Set by | Required | Meaning |
|---|---|---|---|
| `principal` | consumer | yes | Logical identity name; also used as the backend username where applicable. |
| `credentialsSecret.name` | consumer | yes | Kubernetes Secret holding the access/secret key. The **same** Secret the consumer reads. |
| `credentialsSecret.accessKeyKey` | consumer | yes | Key inside the Secret holding the access key. |
| `credentialsSecret.secretKeyKey` | consumer | yes | Key inside the Secret holding the secret key. |
| `buckets` | consumer | yes | Buckets this principal may access. `["*"]` = all. |
| `actions` | consumer | yes | Neutral verbs: `read`, `write`, `list`, `admin` (see below). |
| `sts` | consumer | no (default `false`) | The principal needs to perform `AssumeRole` (STS vended credentials). |

**Action vocabulary** (neutral verbs the provider maps to native permissions):

| Verb | Intent |
|---|---|
| `read` | Get objects / read bucket metadata. |
| `write` | Put / delete objects, multipart uploads. |
| `list` | List bucket contents and buckets. |
| `admin` | Full control on the granted buckets (superset of the above). |

> **Why the credentials appear in both the grant and the consumer.** The grant is the authoritative
> declaration "*this principal must exist with these credentials and this access*". The consumer
> separately reads the same Secret to talk to S3. They point at the **same** Kubernetes Secret; the
> duplication is intentional and is precisely what lets the provider provision access **without**
> reading the consumer's context.

---

## What is *not* in the contract

Anything backend-specific stays **inside the provider's own package** (its KuboCD `schema` /
`parameters`), never in `defaultStorage`. Examples:

| Backend-specific concern | Where it lives |
|---|---|
| SeaweedFS filer metadata database (PostgreSQL) | seaweedfs package parameters |
| SeaweedFS generated auth-config secret name, `sts.enabled` | seaweedfs package |
| RustFS/MinIO root credentials, provisioning `mc` image | rustfs/minio package parameters |
| Storage sizes, replica counts, chart tuning | each package's parameters |

A previous iteration carried a `defaultStorage.settings` block for this. **It is removed from the
contract**: a `settings` shape that fits SeaweedFS does not fit RustFS or AWS, so keeping it shared
would re-introduce backend coupling. The rule is simple — if a field is meaningless for *any* target
backend, it does not belong in the contract.

---

## Capabilities and templating

`region`, `pathStyle` and `tls` are **capabilities**, not decoration. Consumers must template them
rather than hardcode, so the same consumer works on every backend:

```
s3.path-style-access = {{ storage.pathStyle }}
s3.region            = {{ storage.region }}
# scheme/TLS derived from {{ storage.tls }}
```

Self-hosted backends → `pathStyle: true`, `region: dummy`, `tls: true`.
AWS S3 → `pathStyle: false`, a real `region`, `tls: true`.

---

## STS and authorization model

Some consumers (Polaris) obtain **vended, temporary credentials** via `AssumeRole`. The contract
exposes this through:

- `provider.endpoints.stsUrl` — where to call STS;
- `provider.sts.roleArn` — the role ARN to assume (a **provider output**);
- `grants[].sts: true` — the consumer's declaration that it needs AssumeRole.

`sts.roleArn` is a *provider output* because its meaning is backend-specific, while consumers pass
it verbatim:

| Backend | `roleArn` semantics | What authorizes AssumeRole |
|---|---|---|
| SeaweedFS | synthetic ARN, must match the role in `iam.json` | an **admin** identity + a trust policy |
| RustFS / MinIO | **ignored** (credentials-based STS) | the caller having an **admin** policy |
| Ceph RGW | **real** IAM role ARN | a real IAM role + trust policy |
| AWS S3 | **real** IAM role ARN | a real IAM role + trust policy |

Note that `sts: true` is **independent** of the `admin` action: it states a *need*, not a mechanism.
How a provider authorizes it (admin identity, trust policy, …) is a backend detail.

---

## Provisioning boundary

The contract always declares `buckets` and `grants`. **Each provider decides how to honour them** —
the contract shape stays identical across backends:

- **Internal** (SeaweedFS, RustFS, MinIO, Ceph via Rook): the provider *realizes* buckets, users,
  policies and STS roles in its native model.
- **External** (AWS S3, an existing Ceph cluster): the provider is a *no-op* for provisioning — it
  only validates that the declared endpoints and `creds-*` Secrets exist, and wires `sts.roleArn` to
  the real IAM role. Buckets and IAM are managed out of band.

This is the litmus test of neutrality: if the contract can be honoured by a provider that deploys
**nothing** and provisions **nothing** (AWS), it is truly backend-neutral.

### Credential source vs credential contract

The `credentialsSecret` **contract** (secret name + key names) is stable. Only the **source** of the
Secret varies and is invisible to consumers: `local-secrets-provider` / Vault / External Secrets for
self-hosted; IRSA or External Secrets from AWS Secrets Manager for AWS.

---

## Design rules (invariants)

1. **`sts.roleArn` is a provider output, not a constant** — consumers pass it through; providers fill it.
2. **Provisioning may be external** — a provider must be able to do nothing (AWS).
3. **Stable secret contract, variable source** — see above.
4. **Endpoints are single-sourced** — define the backend hostnames in exactly one place; they change with the backend.
5. **Capabilities are templated, not hardcoded** — `pathStyle` / `tls` / `region`.
6. **Backend-only settings live in the provider package** — never in the contract.

---

## Provider implementation guidance

Each provider package (a KuboCD package under `packages/services/<name>/`) is an adapter. It reads
`defaultStorage.{provider,buckets,grants}` and produces native config. Summary of how each backend
maps the contract:

| Provider | Identity/policy model | Bucket creation | STS | Provisioning |
|---|---|---|---|---|
| **SeaweedFS** | `s3` identities (accessKey/secretKey + actions) in a generated auth-config; roles/policies in `iam.json` | chart `createBuckets` | synthetic role + trust policy; admin identity authorizes | internal (chart) |
| **RustFS** | `mc admin user add` + `mc admin policy create/attach`; `admin`/`sts` → attach `consoleAdmin` | `mc mb` (Job) | credentials-based, `roleArn` ignored; admin policy authorizes | internal (`mc` Job) |
| **MinIO** | same as RustFS (`mc`) | `mc mb` | same as RustFS | internal (`mc` Job) |
| **Ceph RGW** | `radosgw-admin` users + IAM roles/policies | admin API / S3 | real IAM role + trust policy | internal (Rook) **or** external |
| **AWS S3** | pre-existing IAM users/roles | pre-existing | real IAM role + trust policy | **external (no-op)** |

**Recipe for a new internal provider:**

1. Deploy the backend (its chart) with root credentials.
2. Map `provider.endpoints` to the backend's S3/STS/console URLs and publish capabilities.
3. Provision `buckets` (idempotently) and, per `grant`, create the principal + a policy from
   `actions`/`buckets`; for `sts`/`admin` grants, grant the backend's admin-equivalent so AssumeRole
   is allowed.
4. Never read a consumer context — everything comes from `buckets`/`grants`.

---

## Compliance checklist

A provider implementation **MUST**:

- [ ] read only `defaultStorage.{provider,buckets,grants}`;
- [ ] publish the full `provider` block (endpoints + capabilities + `sts.roleArn` when STS is used);
- [ ] realize (internal) or validate (external) all declared buckets and grants;
- [ ] keep backend-specific configuration in its own package schema;
- [ ] keep consumers unchanged when it replaces another provider.

A provider implementation **MUST NOT**:

- [ ] reference any consumer context (`.Context.trino`, `.Context.hiveMetastore`,
      `.Context.sparkHistory`, `.Context.polaris`, `.Context.jupyterHub`, …);
- [ ] require consumers to know its backend type;
- [ ] add backend-specific fields to the shared contract.

---

## Contract stability

The contract is intentionally minimal. Any change to `provider`, `buckets` or `grants` is a
**breaking change** for every provider and consumer. Prefer additive, optional fields; treat the
three-part shape as stable. Backend-specific needs are met by provider package parameters, not by
growing the contract.

## References

- Companion ADR (the decision): [`adr/0001-storage-provider-abstraction.md`](../adr/0001-storage-provider-abstraction.md)
- Reference adapter: [`packages/services/seaweedfs/`](../../packages/services/seaweedfs/)
