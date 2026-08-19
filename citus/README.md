# Citus
<!--
SPDX-FileCopyrightText: Copyright © contributors to CloudNativePG, established as CloudNativePG a Series of LF Projects, LLC.
SPDX-License-Identifier: Apache-2.0
-->

[Citus](https://github.com/citusdata/citus) is a PostgreSQL extension that
transforms Postgres into a distributed database, letting you shard tables
and run queries across multiple nodes. For more information, see the
[official documentation](https://docs.citusdata.com/).

> [!NOTE]
> Citus has no official PGDG package, so this image is built from Citus'
> upstream source release instead. See [`Dockerfile`](Dockerfile) for
> details.

> [!WARNING]
> **Experimental, unsupported topology.** The multi-`Cluster`
> coordinator/worker pattern described below is a proof of concept, not an
> officially supported CloudNativePG deployment model: CloudNativePG has no
> native concept of a Citus cluster, so nothing here (node registration,
> failover handling, re-adding a recovered coordinator/worker) is managed or
> validated by the operator. Treat it as a starting point for experimentation
> rather than a production-ready recipe. For example, we've observed benign
> but unexplained `pg_hba`/authentication warnings from Citus' internal
> housekeeping connections (e.g. the coordinator reaching out to itself
> through its own `-rw` Service) that don't affect query correctness but
> whose root cause we haven't fully pinned down.

## Architecture

Unlike most extensions in this repository, Citus is not a drop-in addition
to a single `Cluster`: a Citus deployment is made up of one **coordinator**
node and one or more **worker** nodes, each of which is a regular
PostgreSQL instance. With CloudNativePG, each Citus node is modeled as its
own `Cluster` resource running this extension image, and the nodes are
joined into a single distributed database by:

1. Letting the coordinator and workers reach each other directly over the
   network. Since each node is an independent `Cluster`, this requires
   `pg_hba` rules that accept connections from the other nodes' pods. The
   examples below use CloudNativePG's `podSelectorRefs` field
   (**requires CloudNativePG 1.29 or higher**) to resolve the pods of all
   nodes sharing a `citus.cluster` label into trusted `pg_hba` entries,
   rather than maintaining static IPs or CIDRs.
2. Registering the workers with the coordinator via SQL, using the
   `citus_set_coordinator_host()` and `citus_add_node()` functions. This is
   a manual, one-time (per node) bootstrap step: CloudNativePG has no
   native concept of a Citus cluster, so nothing runs this automatically.

## Usage

### 1. Deploy the coordinator and worker `Cluster`/`Database` resources

The example below deploys a coordinator (`citus`) and two workers
(`citus-p1`, `citus-p2`), all sharing the `citus.cluster: citus` pod label
so they trust each other's pods. Note that this label is set via
`spec.inheritedMetadata`, not the `Cluster`'s own top-level `metadata`:
a `Cluster`'s top-level labels/annotations are **not** propagated to the
pods it creates, while `inheritedMetadata` is — and `podSelectorRefs`
matches against pod labels.

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: citus
spec:
  imageName: ghcr.io/cloudnative-pg/postgresql:18-minimal-trixie
  instances: 1

  storage:
    size: 1Gi

  inheritedMetadata:
    labels:
      citus.cluster: citus
      citus.role: coordinator

  podSelectorRefs:
  - name: citus
    selector:
      matchLabels:
        citus.cluster: citus

  postgresql:
    pg_hba:
    - "hostssl all all ${podselector:citus} trust"
    - "hostssl all all 127.0.0.1/32 trust"
    - "hostssl all all ::1/128 trust"
    shared_preload_libraries:
    - "citus"
    extensions:
    - name: citus
      image:
        # Citus has no PGDG package, so its version is not renovate-tracked;
        # bump it by hand when a new upstream release ships.
        reference: ghcr.io/gbartolini/citus:14.2.0-18-trixie
      ld_library_path:
      - system
---
apiVersion: postgresql.cnpg.io/v1
kind: Database
metadata:
  name: citus-app
spec:
  name: app
  owner: app
  cluster:
    name: citus
  extensions:
  - name: citus
    version: '14.2-1'
---
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: citus-p1
spec:
  imageName: ghcr.io/cloudnative-pg/postgresql:18-minimal-trixie
  instances: 1

  storage:
    size: 1Gi

  inheritedMetadata:
    labels:
      citus.cluster: citus
      citus.role: worker

  podSelectorRefs:
  - name: citus
    selector:
      matchLabels:
        citus.cluster: citus

  postgresql:
    pg_hba:
    - "hostssl all all ${podselector:citus} trust"
    - "hostssl all all 127.0.0.1/32 trust"
    - "hostssl all all ::1/128 trust"
    shared_preload_libraries:
    - "citus"
    extensions:
    - name: citus
      image:
        reference: ghcr.io/gbartolini/citus:14.2.0-18-trixie
      ld_library_path:
      - system
---
apiVersion: postgresql.cnpg.io/v1
kind: Database
metadata:
  name: citus-p1-app
spec:
  name: app
  owner: app
  cluster:
    name: citus-p1
  extensions:
  - name: citus
    version: '14.2-1'
---
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: citus-p2
spec:
  imageName: ghcr.io/cloudnative-pg/postgresql:18-minimal-trixie
  instances: 1

  storage:
    size: 1Gi

  inheritedMetadata:
    labels:
      citus.cluster: citus
      citus.role: worker

  podSelectorRefs:
  - name: citus
    selector:
      matchLabels:
        citus.cluster: citus

  postgresql:
    pg_hba:
    - "hostssl all all ${podselector:citus} trust"
    - "hostssl all all 127.0.0.1/32 trust"
    - "hostssl all all ::1/128 trust"
    shared_preload_libraries:
    - "citus"
    extensions:
    - name: citus
      image:
        reference: ghcr.io/gbartolini/citus:14.2.0-18-trixie
      ld_library_path:
      - system
---
apiVersion: postgresql.cnpg.io/v1
kind: Database
metadata:
  name: citus-p2-app
spec:
  name: app
  owner: app
  cluster:
    name: citus-p2
  extensions:
  - name: citus
    version: '14.2-1'
```

> [!IMPORTANT]
> The `hostssl ... trust` rules above trust *any* pod carrying the
> `citus.cluster: citus` label to connect as *any* role, with no password.
> This is appropriate for traffic between the coordinator and its own
> workers, but only because `podSelectorRefs` scopes it to that specific set
> of trusted pods rather than an open CIDR. Do not broaden the selector to
> include workloads you don't control.

Wait for all three `Cluster` resources to become `Cluster in healthy state`
and their `Database` resources to report `Ready` before continuing.

### 2. Register the workers with the coordinator

CloudNativePG creates a stable `<cluster-name>-rw` Service for the primary
of each `Cluster`. Connect to the coordinator's `app` database (for
example with the [`cnpg` plugin](https://cloudnative-pg.io/docs/current/kubectl-plugin/)):

```console
kubectl cnpg psql citus app
```

and register the coordinator host and each worker by hostname/port of
their respective `-rw` Service:

```sql
SELECT citus_set_coordinator_host('citus-rw', 5432);
SELECT citus_add_node('citus-p1-rw', 5432);
SELECT citus_add_node('citus-p2-rw', 5432);
```

This is a one-time step per node: add one more `citus_add_node()` call
whenever you deploy an additional worker `Cluster` to scale out.

### 3. Verify installation

Still on the coordinator, confirm the extension and the worker topology:

```sql
\dx
SELECT citus_version();
SELECT * FROM citus_get_active_worker_nodes();
```

You should see `citus` (and `citus_columnar`, installed automatically as a
dependency) listed among the extensions, and both `citus-p1-rw` and
`citus-p2-rw` listed as active worker nodes.

From here, tables created on the coordinator can be distributed across the
workers, for example:

```sql
CREATE TABLE events (id bigint, payload jsonb);
SELECT create_distributed_table('events', 'id');

INSERT INTO events (id, payload) VALUES
  (1, '{"type": "signup"}'),
  (2, '{"type": "login"}'),
  (3, '{"type": "purchase"}'),
  (4, '{"type": "login"}'),
  (5, '{"type": "logout"}');

SELECT count(*) FROM events;
```

## Contributors

This extension is maintained by:

- Gabriele Bartolini (@gbartolini)

The maintainers are responsible for:

- Monitoring upstream releases and security vulnerabilities.
- Ensuring compatibility with supported PostgreSQL versions.
- Reviewing and merging contributions specific to this extension's container
  image and lifecycle.

---

## Licenses and Copyright

`citus`:

- **Copyright:** (c) Citus Data, Inc.
- **License:** [GNU Affero General Public License v3.0](https://github.com/citusdata/citus/blob/main/LICENSE) (AGPL-3.0-only)

This image also bundles `libcurl` and a handful of its runtime dependencies
that are not part of the base PostgreSQL image, each under its own license.

All relevant license and copyright information for the `citus` extension
and its dependencies are bundled within the image at:

```text
/licenses/
```

By using this image, you agree to comply with the terms of the licenses
contained therein.
