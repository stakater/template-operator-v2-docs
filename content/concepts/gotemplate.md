# Gotemplate

`Template.spec.gotemplate` is an inline Go template string that renders into one or more Kubernetes manifests. It's the simpler of the two rendering engines and the right choice when you don't need Helm's packaging.

## When to pick gotemplate over helm

- You want one or two resources, not a full release.
- The template is short enough to read inline in the `Template` YAML.
- You don't need conditional sub-charts or release-level lifecycle hooks.
- You want the operator's deletion to cleanly remove every rendered resource (Helm release state isn't managed; gotemplate output is tracked one resource at a time).

## Syntax

The string is parsed with Go's [`text/template`](https://pkg.go.dev/text/template) plus a sandboxed subset of [Sprig functions](https://masterminds.github.io/sprig/). Three functions are removed for safety:

- `env` and `expandenv` would leak the operator pod's environment.
- `getHostByName` would trigger DNS lookups (side effect and SSRF surface).

Everything else from Sprig is available: string manipulation, dates, conditionals, math, encoding.

## Available data

| Path | Value |
|------|-------|
| `.parameters.<name>` | Resolved value for parameter `<name>`. Usually a string; can be a list or map when the value came from an [`objectFieldRef`](./parameters.md#objectfieldref-get-vs-list). |
| `.instance.name` | The consuming `TemplateInstance`'s name. |
| `.instance.namespace` | The consuming `TemplateInstance`'s namespace. |
| `.instance.labels` | The `TemplateInstance`'s labels, as a map. |

The same context is also passed to `helm.valuesTemplate` when using the Helm engine, so anything you learn here transfers.

## Multi-document output

A single `spec.gotemplate` can emit any number of Kubernetes manifests separated by YAML document markers (`---`):

```yaml
spec:
  gotemplate: |
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: {{ .parameters.name }}-config
    data:
      port: "{{ .parameters.port }}"
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
```

## Default namespace

When a rendered manifest omits `metadata.namespace` for a namespaced resource, the operator sets it to the `TemplateInstance`'s namespace before applying. Cluster-scoped resources (e.g. `ClusterRole`, `Namespace`) are applied as-is.

This is what makes `metadata.namespace` optional in most gotemplate bodies: the right value is the consumer namespace anyway, and you don't have to thread it through every manifest.

## Validation at template-creation time

When you create or update a `Template`, the controller:

1. Parses `spec.gotemplate`. Parse failure surfaces as `Valid=False, Reason=ValidationFailed`.
2. If every parameter has a literal `value` default, dry-run renders the template with those defaults and validates that the output is valid YAML. Render failure surfaces as `DryRunRendered=False, Reason=RenderFailed`.
3. If at least one parameter has no literal default, dry-run is skipped: `DryRunRendered=False, Reason=DryRunSkipped`. The `Template` is still considered `Valid` overall; the first end-to-end check happens when the first `TemplateInstance` references it.

Dry-run is skipped rather than guessed at, since the operator has no way to know whether a missing-default parameter will resolve to a string, number, or list at runtime. A guess that doesn't match the runtime type would fail the dry-run on a `Template` that actually works in practice.

## See also

- [Parameters](./parameters.md) for how `.parameters.<name>` is resolved.
- [Using Go templates](../how-to-guides/using-gotemplate.md) for examples.
- [API reference: `TemplateSpec`](../reference/api.md#templatespec).
