# Gotemplate

`Template.spec.gotemplate` is an inline Go template string that renders into one or more Kubernetes manifests. It's the simpler of the two rendering engines and the right choice when you don't need Helm's packaging.

## When to pick gotemplate over helm

- You want one or two resources, not a full release.
- The template is short enough to read inline in the `Template` YAML.
- You don't need conditional sub-charts.
- You want the operator's deletion to cleanly remove every rendered resource (Helm release state isn't managed; gotemplate output is tracked one resource at a time).

## Syntax

The string is parsed with Go's [`text/template`](https://pkg.go.dev/text/template) plus a sandboxed subset of [Sprig functions](https://masterminds.github.io/sprig/). Three functions are removed for safety:

- `env` and `expandenv` would leak the operator pod's environment.
- `getHostByName` would trigger DNS lookups (side effect and SSRF surface).

Everything else from Sprig is available: string manipulation, dates, conditionals, math, encoding.

!!! note "This is Sprig, not Helm"
    `gotemplate` is Go `text/template` with Sprig — **not** Helm templating. Helm-only helpers do not exist here: `toYaml`, `fromYaml`, `include`, `tpl`, `lookup` and `.Files` are all unavailable. For JSON, use Sprig's `mustFromJson` (it decodes both arrays and objects, unlike Helm's map-only `fromJson`) and `toJson`. A handy trick: `toJson` output is valid YAML, so `{{ $obj | toJson }}` stands in for the `toYaml` you might reach for.

## Available data

| Path | Value |
|------|-------|
| `.parameters.<name>` | Resolved value for parameter `<name>`. Usually a string; can be a list or map when the value came from an [`objectFieldRef`](./parameters.md#objectfieldref-get-vs-list). |
| `.instance.name` | The consuming `TemplateInstance`'s name. |
| `.instance.namespace` | The consuming `TemplateInstance`'s namespace. |
| `.instance.labels` | The `TemplateInstance`'s labels, as a map. |

The same context is also passed to `helm.valuesTemplate` when using the Helm engine, so anything you learn here transfers.

## Missing keys are an error

The template is executed with Go's `missingkey=error` option, so reading a map key that does not exist fails the whole render rather than emitting `<no value>`. This bites most often when reading optional fields off a resource pulled in through an [`objectFieldRef`](./parameters.md) parameter — for example `{{ $obj.metadata.labels.team }}` on an object that has no `labels`, or no `team` label, aborts the render.

Read optional keys defensively instead of as struct fields:

```gotemplate
{{- $labels := default dict (index $obj.metadata "labels") }}   {{/* nil-safe */}}
{{- if hasKey $labels "team" }}{{ index $labels "team" }}{{ end }}
```

`index` returns nothing for a missing key, where `$obj.metadata.labels` fails.

`.parameters.<name>` itself is always present (an unresolved required parameter fails earlier, at parameter resolution) — this applies to keys you read *within* a parameter's value.

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
1. If every parameter has a literal `value` default, dry-run renders the template with those defaults and validates that the output is valid YAML. Render failure surfaces as `DryRunRendered=False, Reason=RenderFailed`.
1. If at least one parameter has no literal default, dry-run is skipped: `DryRunRendered=False, Reason=DryRunSkipped`. The `Template` is still considered `Valid` overall; the first end-to-end check happens when the first `TemplateInstance` references it.

Dry-run is skipped rather than guessed at, since the operator has no way to know whether a missing-default parameter will resolve to a string, number, or list at runtime. A guess that doesn't match the runtime type would fail the dry-run on a `Template` that actually works in practice.

## See also

- [Parameters](./parameters.md) for how `.parameters.<name>` is resolved.
- [Using Go templates](../how-to-guides/using-gotemplate.md) for examples.
- [API reference: `TemplateSpec`](../reference/api.md#templatespec).
