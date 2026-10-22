# Deploying Private Helm Charts

A `Template` can pull from a private Helm repository, either an `HTTP`/`HTTPS` repo with basic auth, or an OCI registry with basic auth or a Docker config.

Authentication is configured by referencing a `Secret` from `spec.helm.chart.repository.auth.secretRef`. The `Secret` **must live in the same namespace as the `Template`** (the provider namespace), not the consumer namespace.

## Supported credential layouts

The operator reads the following keys from the referenced `Secret`:

| Source type | Keys | Behavior |
|-------------|------|----------|
| `HTTP`(S) repository | `username`, `password` | Sent as `HTTP` Basic auth on chart pull. |
| OCI registry | `username`, `password` | Sent as `HTTP` Basic auth to the registry. |
| OCI registry | `.dockerconfigjson` | A standard Kubernetes `kubernetes.io/dockerconfigjson` secret. The operator writes it to a temp file and passes it to the OCI client. |

If both `username`/`password` and `.dockerconfigjson` are present in the same secret, `username`/`password` win.

!!! note "Token-based authentication"
    For registries that authenticate with a personal access token, robot token, or API key (GitHub Container Registry, GitLab, Harbor, and similar), place the token in the `password` field of the Secret. Set `username` to whatever value the registry expects, typically your account name or a registry-specific placeholder such as `token` or `oauth2`. The operator passes both fields to Helm as `HTTP` Basic auth; the registry decides how to interpret them.

## Private `HTTPS` repository

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: nexus-creds
  namespace: provider
type: Opaque
stringData:
  username: ci-user
  password: <token-or-password>
---
apiVersion: templates.v2.stakater.com/v2alpha1
kind: Template
metadata:
  name: private-chart
  namespace: provider
spec:
  helm:
    chart:
      repository:
        url: https://nexus.example.com/repository/helm
        name: my-chart
        version: 1.4.0
        auth:
          secretRef:
            name: nexus-creds
    releaseName: my-chart
```

## Private OCI registry: basic auth

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: ghcr-creds
  namespace: provider
type: Opaque
stringData:
  username: ghcr-user
  password: <pat>
---
apiVersion: templates.v2.stakater.com/v2alpha1
kind: Template
metadata:
  name: oci-private
  namespace: provider
spec:
  helm:
    chart:
      repository:
        url: oci://ghcr.io/stakater/charts
        name: my-chart
        version: 0.1.0
        auth:
          secretRef:
            name: ghcr-creds
```

## Private OCI registry: Docker config

If you already have a `kubernetes.io/dockerconfigjson` pull secret, point at it directly:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: ghcr-dockerconfig
  namespace: provider
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: <base64-encoded-config>
---
apiVersion: templates.v2.stakater.com/v2alpha1
kind: Template
metadata:
  name: oci-private-dockerconfig
  namespace: provider
spec:
  helm:
    chart:
      repository:
        url: oci://ghcr.io/stakater/charts
        name: my-chart
        version: 0.1.0
        auth:
          secretRef:
            name: ghcr-dockerconfig
```

## Credentials stay with the provider

The `Secret` lives where the `Template` lives. This keeps registry credentials out of consumer namespaces and gives the platform team full control over chart access. RBAC on the provider namespace is the boundary that protects the credentials.

## Failure modes

If the secret is missing, malformed, or the credentials are wrong, the operator reports:

```yaml
status:
  phase: Error
  conditions:
    - type: SourceAccessible
      status: "False"
      reason: RepositoryUnreachable
      message: "source access failed: failed to pull chart ... unauthorized"
```

The reconcile is retried after 60 seconds, so rotating credentials in-place is non-disruptive.
