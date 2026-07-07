# ADR-0001 — Storage Provider Abstraction

- **Status:** Proposed
- **Date:** 2026-07-06
- **Deciders:** OKDP maintainers
- **Tags:** storage, s3, architecture

## Context

OKDP currently relies on SeaweedFS as its managed object storage backend.

Although data services such as Trino, Hive Metastore, Spark History, JupyterHub and Polaris already consume object storage through the S3 protocol, the current SeaweedFS package is tightly coupled to those services. It directly references their contexts to provision buckets, users, credentials and policies.

This creates an inverted dependency:

- the storage backend knows every storage consumer;
- adding a new consumer requires modifying the storage package;
- adding another storage backend requires duplicating the same provisioning logic;
- switching storage backends becomes an invasive refactoring instead of an infrastructure choice.

As a consequence, OKDP is not truly storage backend agnostic, even though its data services already communicate through a standard S3 API.

## Decision

Introduce a **Storage Provider abstraction** between storage consumers and storage implementations.

Storage consumers must depend only on a stable, backend-neutral storage contract.

Each storage backend (SeaweedFS, RustFS, MinIO, Ceph RGW, AWS S3, ...) implements this contract independently.

The Storage Provider is responsible for:

- exposing storage endpoints;
- provisioning buckets and identities when required;
- exposing authentication and authorization information;
- translating the neutral storage contract into backend-specific resources.

Consumer services must never contain backend-specific logic and storage providers must never depend directly on consumer contexts.

The Storage Provider contract is specified in the companion design document:

> [`docs/design/storage-provider-contract.md`](../design/storage-provider-contract.md)

## Consequences

### Positive

- Storage backends become interchangeable.
- Adding a new backend requires implementing only a new Storage Provider.
- Consumer services remain independent from storage implementations.
- Infrastructure-specific provisioning logic is isolated inside each provider.
- The architecture follows the Dependency Inversion Principle.

### Trade-offs

- The existing SeaweedFS package must be refactored to implement the new abstraction.
- All future storage providers must comply with the shared contract.
- Backend-specific capabilities remain the responsibility of each provider implementation.

## Migration Plan

The migration will be performed incrementally.

### Phase 1

Introduce the Storage Provider contract.

### Phase 2

Refactor the existing SeaweedFS package to implement the contract without changing its functional behavior.

### Phase 3

Implement a RustFS Storage Provider using the same contract.

### Phase 4

Additional providers such as MinIO, Ceph RGW and AWS S3 can be implemented without modifying storage consumers.

## Success Criteria

The architecture is considered successful if switching from one storage backend to another only requires:

- selecting a different Storage Provider;
- deploying the corresponding infrastructure package.

No consumer service should require modification.

## Alternatives considered

### Keep the current SeaweedFS implementation

Rejected because it tightly couples storage provisioning with consumer-specific configuration, preventing backend interchangeability.

### Implement one storage package per backend

Rejected because each backend would duplicate the same provisioning logic for every consumer, making maintenance increasingly difficult.

### Let each consumer provision its own storage resources

Rejected because infrastructure responsibilities would be spread across multiple services, leading to duplicated logic and tighter coupling between applications and storage infrastructure.

### Standardize only on the S3 API

Rejected because S3 compatibility alone is insufficient.

OKDP also needs backend provisioning capabilities such as bucket creation, identity management, policy generation and STS configuration. Those responsibilities require a provider abstraction in addition to the S3 protocol.

## References

- Companion design document: [`docs/design/storage-provider-contract.md`](../design/storage-provider-contract.md)