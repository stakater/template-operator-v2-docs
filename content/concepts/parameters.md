# Parameters

Parameters bridge the provider's `Template` and the consumer's `TemplateInstance`. The provider declares what the template accepts; the consumer supplies values. The operator resolves the merge at render time.

## Two sides

Parameters appear in two places:

- **`Template.spec.parameters`**: provider-side declarations. Each declares a parameter name and may set a literal default, a type, and override rules.
- **`TemplateInstance.spec.parameters`**: consumer-side overrides. Each is either a literal `value` or a dynamic `valueFrom` that resolves at render time.

A parameter name in the instance must match a name declared on the `Template`. Unknown names are rejected with `ParametersValid=False, Reason=InvalidParameter`.

## Resolution

For each parameter declared on the `Template`:

1. If the `TemplateInstance` overrides it, the override is resolved (literal or `valueFrom`).
1. Otherwise the `Template`'s `value` default is used.
1. If neither exists, resolution fails: `ParametersValid=False, Reason=ParameterResolutionFailed`.

Resolution is **fail-fast**: if any single parameter can't be resolved, the entire `TemplateInstance` does not render. Rendering with missing parameter values would produce non-deterministic manifests that are rarely safe to apply.

## Provider-side declarations

A `TemplateParameterDefinition` is the shape of one entry in `Template.spec.parameters`.

| Field | Purpose |
|-------|---------|
| `name` | Required. Must be unique within the `Template`. |
| `value` | Optional literal default. |
| `type` | Optional. One of `string`, `number`, `bool`. Validates both the default and any instance override. |
| `required` | Optional. When `true`, the `TemplateInstance` MUST provide a value (the `Template` default, if any, is ignored). |
| `disableOverride` | Optional. When `true`, the `TemplateInstance` MUST NOT supply its own value. |
| `exposeInStatus` | Optional. When `true`, the resolved value is recorded in `status.resolvedParameters[].value`. |

!!! note "`required` and `disableOverride` cannot both be `true`"
    The combination is rejected by CRD-level validation. `required` demands a consumer override; `disableOverride` forbids one.

### `type` and what it validates

`type` is a validation hint:

- `string`: any value is accepted.
- `number`: must parse via Go's `strconv.ParseFloat` (e.g. `"3"`, `"3.14"`, `"-2.5e10"` are accepted; `"three"` is rejected).
- `bool`: must parse via `strconv.ParseBool` (e.g. `"true"`, `"false"`, `"1"`, `"0"` are accepted; `"yes"` is rejected).

!!! important
    `type` applies to scalar parameters only. When an `objectFieldRef` resolves to a list or map, it cannot satisfy a scalar `type` such as `string`.

### `required` semantics

A `required: true` parameter forces the consumer to override it. Even if the `Template` has a `value` default, the default is ignored; the consumer must supply a value.

**Usage**: for values the consumer must consciously choose, such as database hostnames, TLS certificate names, or namespace selectors. Avoid `required` for parameters that already have safe defaults, since it forces every `TemplateInstance` to redeclare values the `Template` could have provided.

### `disableOverride` semantics

A `disableOverride: true` parameter is read-only from the consumer's point of view. An attempted override surfaces as `ParametersValid=False, Reason=OverrideNotAllowed`.

**Usage**: for values the platform team owns, such as image registries, mandatory labels, or security-relevant settings.

### `exposeInStatus` semantics

By default `status.resolvedParameters[]` only records the *source* of each parameter (which literal, or which `valueFrom`). The resolved value itself is **not** written to status; useful when values may be secrets.

`exposeInStatus: true` opts a specific parameter into having its resolved value written to `status.resolvedParameters[].value`.

!!! warning
    `exposeInStatus: true` should be treated as a declaration that the parameter's value is public information. Never set it on parameters resolved from a `Secret`.

## Instance-side overrides

A `TemplateParameter` on the `TemplateInstance` has three shapes:

1. **Literal**: `value: "..."`.
1. **Dynamic**: `valueFrom: { ... }` reading from a cluster resource.
1. **Dynamic with fallback**: `valueFrom: { ... }` plus `defaultValue: "..."`.

### Validation rules

The CRD rejects a `TemplateInstance` parameter that:

- Sets neither, or both, of `value` and `valueFrom`.
- Sets `defaultValue` without `valueFrom`.
- Sets both `value` and `defaultValue`.

### `valueFrom.secretKeyRef` and `configMapKeyRef`

Read a specific key from a `Secret` or `ConfigMap`. `Secret` values are base64-decoded automatically. `namespace` is optional and defaults to the `TemplateInstance`'s namespace.

```yaml
valueFrom:
  secretKeyRef:
    name: db-credentials
    key: password
```

### `objectFieldRef` (GET vs LIST)

`objectFieldRef` evaluates a JSONPath against any cluster resource, identified by GVK.

**GET mode**, when `name` is set, the operator GETs that one resource and evaluates the JSONPath against it. Returns a scalar.

```yaml
valueFrom:
  objectFieldRef:
    apiVersion: networking.k8s.io/v1
    kind: Ingress
    name: my-ingress
    namespace: team-a
    jsonPath: .status.loadBalancer.ingress[0].ip
```

**LIST mode**, when `name` is omitted, the operator LISTs all resources of the GVK and evaluates the JSONPath against the list. **Always returns a list**, even for single matches, so templates can `{{range}}` safely.

```yaml
valueFrom:
  objectFieldRef:
    apiVersion: v1
    kind: ConfigMap
    namespace: team-alpha
    jsonPath: .items[*].metadata.name
```

Namespace scoping for `objectFieldRef`:

- Set → operate in that namespace only.
- Omitted → for namespaced GVKs, operate across all namespaces; for cluster-scoped GVKs, the field is ignored.

GET mode always requires a namespace for namespaced GVKs.

JSONPath rules:

- Must start with a dot (`.metadata.name`).
- Do not wrap in `{}`; the operator wraps it internally.

### `defaultValue` semantics

`defaultValue` is used only when paired with `valueFrom`, and applies whenever the `valueFrom` resolution **fails** for any reason: the resource doesn't exist, the key is missing, the GVK can't be mapped, the JSONPath matches nothing, and so on.

```yaml
valueFrom:
  secretKeyRef:
    name: db-credentials
    key: password
defaultValue: changeme
```

- `Secret` doesn't exist → resolution fails → `changeme` is used.
- `Secret` exists but the `password` key is missing → resolution fails → `changeme` is used.
- `Secret` exists, key exists, value is `""` → resolution succeeds with an empty value, which is used as-is. `defaultValue` is **not** applied to successfully-resolved empty values.

## Watch semantics

For every `valueFrom` source, the operator registers a watch via its dynamic informer registry. Changes to the source trigger re-reconciliation of the `TemplateInstance`. This is how secret rotation, ConfigMap edits, and ingress IP assignment propagate without a manual `kubectl edit`.

This applies to `sync.mode: revert` and `strict` only. With `sync.mode: off`, the instance freezes after its first clean apply: the parameter watches are released, and source changes no longer propagate — see [Sync](sync.md).

If the GVK referenced by an `objectFieldRef` cannot be resolved (for example, a CRD that isn't installed), the operator skips setting up a watch for that source. Parameter resolution will still fail at reconcile time, surfaced as `ParametersValid=False, Reason=ParameterResolutionFailed`.

## RBAC

The operator's service account needs `get`, `list`, and `watch` on every GVK referenced by `objectFieldRef`. Standard core resources (`Secret`, `ConfigMap`, `Namespace`) are pre-granted by the chart. Adding new resource kinds to your `objectFieldRef` set requires granting the operator additional permissions.

## See also

- [Parameters and overrides](../how-to-guides/parameters-and-overrides.md) for examples.
- [Parameter validation](../how-to-guides/parameter-validation.md) for guidance on choosing `type` / `required` / `disableOverride` / `exposeInStatus`.
- [API reference: `TemplateParameterDefinition`](../reference/api.md#templateparameterdefinition) and [`TemplateParameter`](../reference/api.md#templateparameter).
