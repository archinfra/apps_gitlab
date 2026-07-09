# apps_gitlab

GitLab offline delivery repository for Kubernetes.

This repository follows the same delivery contract as `apps_redis-cluster`: it builds a self-contained `.run` package containing GitLab manifests, image metadata, and container image tar files. The installer can import images into an internal registry, install GitLab into Kubernetes, keep data persisted by PVCs, expose GitLab through Envoy Gateway API, enable external OIDC login, and optionally configure GitLab external authorization.

## What This Installer Deploys

This package deploys a single-node GitLab CE Omnibus instance as a Kubernetes `StatefulSet`.

It creates:

- `Namespace`
- `ConfigMap` for `GITLAB_OMNIBUS_CONFIG`
- `Secret` for initial root password and optional OIDC client secret
- `Service` for HTTP and SSH inside the cluster
- `StatefulSet` with startup, readiness, and liveness probes
- three persistent volume claim templates:
  - `/etc/gitlab`
  - `/var/log/gitlab`
  - `/var/opt/gitlab`
- `PodDisruptionBudget`
- optional Gateway API `HTTPRoute`
- optional Gateway API `TCPRoute` for SSH

This is a stable single-node GitLab deployment, not a full GitLab HA topology. For very large production use, split PostgreSQL, Redis, Gitaly and object storage outside the Omnibus pod or migrate to the official GitLab chart architecture.

## Quick Start

Build the offline package:

```bash
cd apps_gitlab
bash -n build.sh install.sh
jq empty images/image.json
bash build.sh --arch amd64
```

Install with defaults:

```bash
./dist/gitlab-installer-amd64.run install -y
```

Install using a storage class and a public hostname:

```bash
./dist/gitlab-installer-amd64.run install \
  --storage-class nfs \
  --hostname gitlab.aisphere.local \
  --root-password 'GitLab@ChangeMe123' \
  -y
```

Install when images already exist in the internal registry:

```bash
./dist/gitlab-installer-amd64.run install \
  --registry sealos.hub:5000/kube4 \
  --skip-image-prepare \
  -y
```

## External OIDC

Create an OIDC application for GitLab and configure its redirect URI as:

```text
https://gitlab.aisphere.local/users/auth/openid_connect/callback
```

Then install GitLab with OIDC enabled:

```bash
./dist/gitlab-installer-amd64.run install \
  --hostname gitlab.aisphere.local \
  --enable-oidc \
  --oidc-issuer https://casdoor.aisphere.local \
  --oidc-client-id gitlab \
  --oidc-client-secret 'replace-me' \
  --oidc-label Casdoor \
  --oidc-uid-field sub \
  -y
```

The generated Omnibus config enables GitLab OmniAuth with the `openid_connect` provider. It uses `sub` as the default UID field because it is expected to be stable and immutable.

## External Authorization Service

GitLab external authorization is configured after the StatefulSet is ready by running `gitlab-rails runner` inside the GitLab pod. This is intentional: external authorization is stored in GitLab application settings rather than only in static Kubernetes manifests.

Enable external authorization:

```bash
./dist/gitlab-installer-amd64.run install \
  --hostname gitlab.aisphere.local \
  --enable-external-authz \
  --external-authz-url http://iam.aisphere.svc.cluster.local:8080/v1/gitlab/authz \
  --external-authz-default-label aisphere \
  -y
```

Enable OIDC and external authorization together:

```bash
./dist/gitlab-installer-amd64.run install \
  --hostname gitlab.aisphere.local \
  --enable-oidc \
  --oidc-issuer https://casdoor.aisphere.local \
  --oidc-client-id gitlab \
  --oidc-client-secret 'replace-me' \
  --enable-external-authz \
  --external-authz-url http://iam.aisphere.svc.cluster.local:8080/v1/gitlab/authz \
  --external-authz-default-label aisphere \
  -y
```

Disable external authorization explicitly:

```bash
./dist/gitlab-installer-amd64.run install \
  --disable-external-authz \
  -y
```

External authorization options:

| Option | Meaning |
| --- | --- |
| `--enable-external-authz` | enable GitLab external authorization after rollout |
| `--disable-external-authz` | disable GitLab external authorization after rollout |
| `--external-authz-url <url>` | external authorization service URL; required when enabling |
| `--external-authz-default-label <val>` | default project classification label, default `aisphere` |
| `--external-authz-retries <num>` | retry count for `gitlab-rails runner`, default `30` |
| `--external-authz-retry-interval <s>` | retry interval in seconds, default `10` |
| `--external-authz-best-effort` | do not fail install if the running GitLab version does not expose the expected ApplicationSetting fields |

GitLab sends the external service a JSON `POST` with user and project classification data. Your service should return `200` to allow access and `401` or `403` to deny access. A typical adapter can map `user_identifier` or OIDC `identities` to an internal user, then query SpiceDB or another policy engine.

Suggested adapter contract:

```text
GitLab
  -> POST /v1/gitlab/authz
      user_identifier
      project_classification_label
      identities[]
  -> IAM / SpiceDB adapter
  -> 200 allow, 401/403 deny
```

## Envoy Gateway API Exposure

HTTP exposure is enabled by default through an `HTTPRoute`:

```bash
./dist/gitlab-installer-amd64.run install \
  --hostname gitlab.aisphere.local \
  --gateway-name aisphere-gateway \
  --gateway-namespace aisphere \
  --gateway-http-section https \
  -y
```

If Gateway API CRDs are not present, the installer skips route creation by default. To fail fast when the route cannot be created:

```bash
./dist/gitlab-installer-amd64.run install --require-gateway -y
```

To disable Gateway API exposure:

```bash
./dist/gitlab-installer-amd64.run install --disable-gateway -y
```

SSH clone/push through Gateway API requires a TCP listener on the Gateway and TCPRoute support:

```bash
./dist/gitlab-installer-amd64.run install \
  --enable-ssh-route \
  --gateway-ssh-section ssh \
  --ssh-external-port 22 \
  -y
```

If SSH through Gateway is not enabled, users can still use Git over HTTPS through the HTTPRoute.

## Default Deployment Contract

| Item | Default |
| --- | --- |
| namespace | `gitlab-system` |
| release name | `gitlab` |
| public hostname | `gitlab.aisphere.local` |
| external URL | `https://gitlab.aisphere.local` |
| storage class | `nfs` |
| config PVC | `5Gi` |
| logs PVC | `20Gi` |
| data PVC | `100Gi` |
| resource profile | `mid` |
| image pull policy | `IfNotPresent` |
| wait timeout | `30m` |
| target registry repo | `sealos.hub:5000/kube4` |
| Gateway HTTPRoute | enabled |
| OIDC | disabled unless `--enable-oidc` is set |
| external authorization | unchanged unless `--enable-external-authz` or `--disable-external-authz` is set |

Default image metadata is in `images/image.json`:

```json
[
  {
    "name": "gitlab-ce",
    "arch": "amd64",
    "platform": "linux/amd64",
    "pull": "gitlab/gitlab-ce:18.6.4-ce.0",
    "tag": "sealos.hub:5000/kube4/gitlab-ce:18.6.4-ce.0",
    "tar": "gitlab-ce-amd64.tar"
  }
]
```

## Resource Profiles

| Profile | CPU request | CPU limit | Memory request | Memory limit | Scenario |
| --- | --- | --- | --- | --- | --- |
| `low` | `2` | `4` | `6Gi` | `8Gi` | demo or small internal validation |
| `mid` | `4` | `8` | `8Gi` | `12Gi` | normal shared internal GitLab |
| `high` | `8` | `16` | `16Gi` | `24Gi` | heavier repository and CI metadata usage |

GitLab first boot is slow. The default startup probe allows up to about 15 minutes before declaring startup failure, and the installer waits up to `30m` by default.

## Persistence And Stability Design

The installer is intentionally conservative:

- GitLab is a `StatefulSet`, not a stateless `Deployment`.
- `/etc/gitlab`, `/var/log/gitlab`, and `/var/opt/gitlab` are persisted independently.
- PVCs use the configured `StorageClass` and `ReadWriteOnce` access mode.
- `terminationGracePeriodSeconds` is `300`.
- `preStop` calls `gitlab-ctl stop` before pod termination.
- startup, readiness, and liveness probes target `/users/sign_in`.
- `PodDisruptionBudget` keeps `minAvailable: 1`.
- uninstall preserves PVCs unless `--delete-pvc` is explicitly provided.

## Offline Delivery Flow

Build side:

1. `build.sh` reads `images/image.json`.
2. It pulls the GitLab image for the selected architecture.
3. It tags the image into a local payload reference.
4. It saves the image to `payload/images/*.tar`.
5. It writes `payload/images/image-index.tsv`.
6. It vendors `manifests/` into the payload.
7. It appends the payload to `install.sh` to produce `dist/gitlab-installer-<arch>.run`.

Install side:

1. the `.run` extracts its embedded payload by byte offset
2. it loads image metadata
3. it optionally `docker load`, retags and pushes images to the target registry
4. it renders Kubernetes manifests
5. it applies the StatefulSet, Services, PVC templates and Gateway routes
6. it waits for StatefulSet rollout
7. if requested, it configures external authorization with `gitlab-rails runner`

## Common Commands

Show help:

```bash
./dist/gitlab-installer-amd64.run help
```

Check status:

```bash
./dist/gitlab-installer-amd64.run status -n gitlab-system
```

Uninstall while preserving PVC data:

```bash
./dist/gitlab-installer-amd64.run uninstall -n gitlab-system -y
```

Uninstall and delete PVC data:

```bash
./dist/gitlab-installer-amd64.run uninstall -n gitlab-system --delete-pvc -y
```

## Validation Checklist

Before release:

```bash
bash -n build.sh install.sh
jq empty images/image.json
bash build.sh --arch amd64
sha256sum -c dist/gitlab-installer-amd64.run.sha256
```

In a cluster with pre-pushed images:

```bash
./dist/gitlab-installer-amd64.run install \
  --skip-image-prepare \
  --storage-class nfs \
  --hostname gitlab.aisphere.local \
  --enable-oidc \
  --oidc-client-id gitlab \
  --oidc-client-secret 'replace-me' \
  --enable-external-authz \
  --external-authz-url http://iam.aisphere.svc.cluster.local:8080/v1/gitlab/authz \
  -y
```
