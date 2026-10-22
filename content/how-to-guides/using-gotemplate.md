# Using Go Templates

`spec.gotemplate` is an inline Go template that renders into one or more Kubernetes manifests. It uses Go's [`text/template`](https://pkg.go.dev/text/template) syntax with [Sprig functions](https://masterminds.github.io/sprig/).

## Template variables

The following variables are available inside the template:

| Path | Description |
|------|-------------|
| `.parameters.<name>` | Resolved value for parameter `<name>`. |
| `.instance.name` | Name of the consuming `TemplateInstance`. |
| `.instance.namespace` | Namespace of the consuming `TemplateInstance`. |
| `.instance.labels` | The `TemplateInstance`'s labels, as a map. |

## Example: ConfigMap and Service

```yaml
apiVersion: templates.v2.stakater.com/v2alpha1
kind: Template
metadata:
  name: app-bundle
  namespace: provider
spec:
  parameters:
    - name: name
    - name: port
      value: "8080"
    - name: env
      value: production
  gotemplate: |
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: {{ .parameters.name }}-config
      labels:
        app: {{ .parameters.name }}
        env: {{ .parameters.env }}
    data:
      PORT: "{{ .parameters.port }}"
      INSTANCE: {{ .instance.name }}
    ---
    apiVersion: v1
    kind: Service
    metadata:
      name: {{ .parameters.name }}
    spec:
      selector:
        app: {{ .parameters.name }}
      ports:
        - port: {{ .parameters.port }}
          targetPort: {{ .parameters.port }}
```

A single `gotemplate` may emit any number of manifests separated by `---`. The operator parses each non-empty document as one rendered resource.

## Default namespace handling

If a rendered manifest omits `metadata.namespace` for a namespaced resource, the operator sets it to the `TemplateInstance`'s namespace before applying. Cluster-scoped resources (e.g. `ClusterRole`, `Namespace`) are applied as-is.

## Sprig examples

```yaml
spec:
  gotemplate: |
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: {{ .parameters.name | lower }}-config
      labels:
        app: {{ .parameters.name | lower }}
    data:
      uppercased: {{ .parameters.name | upper | quote }}
      generated: {{ now | date "2006-01-02" }}
      hash: {{ .parameters.name | sha256sum | trunc 8 }}
```

## Iterating over list-valued parameters

When a parameter is resolved via `objectFieldRef` in LIST mode, the value is always a list. Iterate with `range`:

```yaml
spec:
  parameters:
    - name: serviceNames
  gotemplate: |
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: discovered-services
    data:
      services: |
        {{- range .parameters.serviceNames }}
        - {{ . }}
        {{- end }}
```

## Validation behavior

When the `Template` is created or updated, the controller:

1. Parses the template string. A parse error sets `Valid=False, Reason=ValidationFailed`.
1. If every parameter has a literal `value`, the controller dry-run renders the template with those values and validates the YAML output. Any rendering or YAML validation error sets `DryRunRendered=False, Reason=RenderFailed`.
1. If even one parameter is dynamic (no literal `value`), the dry-run is skipped and the controller sets `DryRunRendered=False, Reason=DryRunSkipped`. The `Template` is still considered `Valid` overall.

This means a `Template` with parameters that are resolved at the `TemplateInstance` level will not be dry-run rendered at template-creation time. The first end-to-end validation happens when the first `TemplateInstance` is created.

## Restrictions

- The output must be parseable as YAML once rendered.
- Each top-level manifest must be a valid Kubernetes object (have `apiVersion`, `kind`, `metadata.name`).
- Empty documents between `---` separators are skipped.
