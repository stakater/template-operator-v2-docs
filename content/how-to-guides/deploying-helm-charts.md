# Deploying Helm Charts

Examples of using a Helm chart as a `Template`'s body. For the chart-source rules, Helm SDK selection, `valuesTemplate`, release-name semantics, and validation behavior, see [Helm](../concepts/helm.md). For private repositories, see [Deploying private Helm charts](./deploying-private-helm-charts.md).

## Scenario 1: public HTTPS repository

Bill publishes the upstream `nginx` chart from Bitnami, parameterized so each consumer can pick a replica count.

```yaml
apiVersion: templates.v2.stakater.com/v2alpha1
kind: Template
metadata:
  name: nginx-template
  namespace: provider
spec:
  helm:
    chart:
      repository:
        url: https://charts.bitnami.com/bitnami
        name: nginx
        version: 18.1.0
    releaseName: nginx
    valuesTemplate: |
      replicaCount: {{ .parameters.replicas }}
      service:
        type: ClusterIP
  parameters:
    - name: replicas
      value: "2"
  targetNamespaces:
    explicit:
      allow:
        literal:
          - team-a
```

A consuming `TemplateInstance`:

```yaml
apiVersion: templates.v2.stakater.com/v2alpha1
kind: TemplateInstance
metadata:
  name: nginx
  namespace: team-a
spec:
  templateRef:
    name: nginx-template
    namespace: provider
  parameters:
    - name: replicas
      value: "3"
```

## Scenario 2: OCI registry

OCI-hosted charts use the `oci://` scheme. Everything else is identical to the HTTPS case:

```yaml
spec:
  helm:
    chart:
      repository:
        url: oci://ghcr.io/stakater/charts
        name: my-chart
        version: 0.1.0
```

## Scenario 3: driving values from instance metadata

`valuesTemplate` is a Go template, so the consuming `TemplateInstance`'s name, namespace, and labels are available alongside parameters:

```yaml
spec:
  helm:
    chart:
      repository:
        url: https://charts.example.com
        name: app
        version: 1.0.0
    valuesTemplate: |
      ingress:
        enabled: true
        hosts:
          - host: {{ .instance.name }}.example.com
            paths:
              - path: /
                pathType: Prefix
      resources:
        limits:
          cpu: {{ .parameters.cpuLimit }}
          memory: {{ .parameters.memLimit }}
  parameters:
    - name: cpuLimit
      value: "500m"
    - name: memLimit
      value: "256Mi"
```

Each `TemplateInstance` automatically gets an ingress host derived from its own name.

## Repository URL rules

- `spec.helm.chart.repository.url` must match the pattern `^(https?|oci)://`.
- `version` must follow [SemVer 2](https://semver.org), e.g. `1.2.3`, `v1.2.3`, `1.2.3-rc.1+meta`. Ranges, `latest`, and floating versions are rejected at admission time.

## Status on failure

If the chart cannot be pulled, the `Template` reports:

```yaml
status:
  phase: Error
  conditions:
    - type: SourceAccessible
      status: "False"
      reason: RepositoryUnreachable
      message: "source access failed: failed to pull chart..."
```

The reconcile is retried after 60 seconds, so transient registry outages self-heal. See [Helm](../concepts/helm.md#validation-at-template-creation-time) for the full set of conditions and reasons set during validation.

## See also

- [Helm](../concepts/helm.md) for the model, SDK selection, and `valuesTemplate` rendering.
- [Deploying private Helm charts](./deploying-private-helm-charts.md) for auth Secrets and registry tokens.
- [API reference: `HelmSpec`](../reference/api.md#helmspec).
