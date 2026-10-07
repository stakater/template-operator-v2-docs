# Key Features

## Two template engines

A `Template` exposes exactly one of two engines, enforced by an API-level validation rule (`has(self.gotemplate) != has(self.helm)`).

### Go template

`spec.gotemplate` is a string parsed with Go's [`text/template`](https://pkg.go.dev/text/template) plus [Sprig functions](https://masterminds.github.io/sprig/). The output may emit one or more Kubernetes manifests separated by YAML document markers. The following Sprig functions are removed for safety: `env`, `expandenv`, `getHostByName`.

### Helm

`spec.helm` references a chart by repository URL, chart name, and `SemVer` 2 version:

- `HTTP`/`HTTPS` repositories: `url: https://charts.example.com`
- OCI registries: `url: oci://ghcr.io/org/charts`

Both Helm v3 and v4 SDKs are bundled. Pick with `spec.helm.version: v3` or `v4`. When omitted, `v4` is the default. Optional `spec.helm.valuesTemplate` is itself a Go template that, after rendering, is parsed as YAML and merged over the chart's default values.

Private repositories are supported via `spec.helm.chart.repository.auth.secretRef`, which references a `Secret` in the **Template's** namespace (not the consumer's).

## Available data

Both engines see the same context object:

- `.parameters`, the resolved parameter map.
- `.instance.name`, `.instance.namespace`, `.instance.labels`, metadata of the consuming `TemplateInstance`.

!!! important
    If a rendered manifest omits `metadata.namespace`, the operator sets it to the `TemplateInstance`'s namespace before applying.

## Dynamic parameter resolution

`TemplateInstance` parameter overrides may resolve their value at render time:

| Source | Field | Reads |
|--------|-------|-------|
| Secret | `valueFrom.secretKeyRef` | A specific key, base64-decoded |
| ConfigMap | `valueFrom.configMapKeyRef` | A specific key |
| Any resource | `valueFrom.objectFieldRef` | A JSONPath expression evaluated against the resource (GET mode) or against a list of resources (LIST mode, when `name` is omitted) |

`objectFieldRef` returns a scalar in GET mode; it always returns a list in LIST mode so templates can `{{range}}` safely. The operator dynamically watches every resource referenced by `valueFrom`, and re-reconciles the `TemplateInstance` when the source changes.

A `defaultValue` may be set on each `TemplateInstance` parameter; it is used only when paired with `valueFrom`, and applies whenever the `valueFrom` resolution fails (missing resource, missing key, JSONPath error, and so on).

## Target namespace control

`Template.spec.targetNamespaces` decides which consumer namespaces are allowed to instantiate the `Template`:

- Omitted entirely → same namespace as the `Template` only (default).
- `explicit.allow.literal: ["*"]` → all namespaces.
- `explicit.allow.literal: [...]` → explicit allow-list.
- `selector` → namespaces whose labels match the `LabelSelector`.
- A namespace is permitted if it matches the explicit list **or** the selector.

If a `TemplateInstance` is created in a non-permitted namespace, the controller sets the `TargetNamespaceAllowed` condition to `False` and refuses to render.

## Lifecycle and clean-up

- Every rendered resource carries a finalizer (`templates.v2.stakater.com/template-instance-resource`) so the operator can clean up before the API server garbage-collects.
- `Template` deletion is **blocked** while any `TemplateInstance` references it, the controller publishes the `Deleting` condition with reason `DeletionBlocked`.
- `TemplateInstance` deletion sweeps every resource recorded in `status.renderedResources`, removes the finalizer, then removes its own finalizer.

## Status reporting

Every CR exposes:

- `status.phase`, `Valid`/`Invalid`/`Error` for `Template`; `Ready`/`Failed` for `TemplateInstance`.
- `status.observedGeneration`, last `metadata.generation` reconciled.
- `status.conditions[]`, Kubernetes-standard with `Type`, `Status`, `Reason`, `Message`, `LastTransitionTime`, `ObservedGeneration`.

`TemplateInstance` additionally exposes:

- `status.resolvedParameters`, the source map for each parameter after merging defaults and overrides.
- `status.renderedResources`, identity (`apiVersion`/`kind`/`name`/`namespace`) plus per-resource `observedGeneration` and `status` (empty for successfully applied, `Failed` when the operator is retrying) for every applied resource.
- `status.resolvedTemplateRef`, the `name`/`namespace`/`generation` of the `Template` that was actually rendered.

## Validation at template-creation time

The `Template` controller dry-run renders new and updated templates as soon as they are created. For Helm templates this includes pulling the chart, verifying the source is reachable, and rendering with the `valuesTemplate` output. The result is reported via:

- `Valid`, template spec parses and renders.
- `SourceAccessible`, for Helm: chart could be pulled.
- `DryRunRendered`, render produces valid YAML.

Dry-run is skipped when any parameter has no literal default value (since the runtime type cannot be guessed safely).
