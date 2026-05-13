# Helm

`Template.spec.helm` references a Helm chart instead of an inline template. The operator pulls the chart at validation time, renders it with merged values at instance time, and applies the result. Both Helm v3 and v4 SDKs are bundled.

## When to pick helm over gotemplate

- The thing you want to deploy is already packaged as a Helm chart (cert-manager, kube-prometheus-stack, your own internal charts).
- The output is large enough that maintaining it inline as a gotemplate is awkward.
- You want chart-level versioning (the `version` field of `spec.helm.chart.repository` pins a SemVer).

For ad-hoc resources that don't already have a chart, [gotemplate](./gotemplate.md) is lighter weight.

## Chart source

A chart is identified by three required fields: the repository URL, the chart name within the repository, and the exact version.

```yaml
spec:
  helm:
    chart:
      repository:
        url: https://charts.bitnami.com/bitnami
        name: nginx
        version: 18.1.0
```

- **HTTP/HTTPS repositories**: `url: https://...`. The repository must expose an `index.yaml`.
- **OCI registries**: `url: oci://...`. The chart reference becomes `<url>/<name>:<version>`.
- **Version**: must match SemVer 2 (`MAJOR.MINOR.PATCH`, with optional pre-release and build metadata). Ranges, `latest`, or floating versions are rejected.

## Helm v3 vs v4

`spec.helm.version` is `v3` or `v4`; defaults to `v4`. Both SDKs are linked into the controller, and `Template.spec.helm.version` is a runtime switch, there's no separate operator deployment per Helm version.

!!! tip
    Pick `v4` unless a chart relies on v3-specific behavior the v4 SDK doesn't replicate.

## Release name

`spec.helm.releaseName` is optional. When omitted, the operator uses the consuming `TemplateInstance.metadata.name` as the release name.

!!! note
    Helm caps release names at 53 characters; the API enforces that limit too.

## ValuesTemplate

`spec.helm.valuesTemplate` is itself a Go template (same syntax as [gotemplate](./gotemplate.md), same `.parameters` / `.instance` context). Its rendered output is parsed as YAML and merged over the chart's default `values.yaml`.

```yaml
spec:
  helm:
    chart: { repository: { url: ..., name: ..., version: ... } }
    valuesTemplate: |
      replicaCount: {{ .parameters.replicas }}
      ingress:
        hosts:
          - host: {{ .instance.name }}.example.com
            paths: [{ path: /, pathType: Prefix }]
```

The output must be a YAML mapping at the top level (a list or scalar is rejected). The operator validates this at `Template` creation time.

## Authentication

Private repositories use `spec.helm.chart.repository.auth.secretRef`, which references a `Secret` in the **provider** namespace (the same namespace as the `Template`).

```yaml
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

Supported credential layouts:

| Source | Secret keys | Behavior |
|--------|-------------|----------|
| HTTP(S) | `username`, `password` | Basic auth on the pull request. |
| OCI | `username`, `password` | Used as registry basic auth. |
| OCI | `.dockerconfigjson` (a `kubernetes.io/dockerconfigjson` Secret) | The operator writes the config to a temp file and passes it to the OCI client. |

The credential never has to be replicated to consumer namespaces; the provider holds it, and the operator pulls on the consumer's behalf.

## Render mode

The operator runs Helm in client-side dry-run mode (equivalent of `helm template`), with:

- `IncludeCRDs: true`: CRDs in the chart are included.
- `DisableOpenAPIValidation: true`: the API server does validation at apply time.
- `Replace: true`: release name reuse is allowed.

## Validation at template-creation time

When a `Template` with `spec.helm` is created or updated:

1. If `valuesTemplate` is set, it's rendered with dummy parameters. Failure → `Valid=False`.
2. The chart is pulled. Failure → `SourceAccessible=False, Reason=RepositoryUnreachable`. The reconcile requeues after 60 s so transient registry outages self-heal.
3. The chart is rendered with the dummy values. Failure → `DryRunRendered=False, Reason=RenderFailed`.
4. The rendered manifest YAML is validated. Failure → `Valid=False, Reason=ValidationFailed`.

## See also

- [Deploying Helm charts](../how-to-guides/deploying-helm-charts.md) and [Deploying private Helm charts](../how-to-guides/deploying-private-helm-charts.md) for examples.
- [Parameters](./parameters.md) for how `.parameters.<name>` is resolved inside `valuesTemplate`.
- [API reference: `HelmSpec`](../reference/api.md#helmspec).
