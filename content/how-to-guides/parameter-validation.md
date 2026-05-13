# Parameter Validation

`TemplateParameterDefinition` exposes four optional fields beyond `name` and `value` that let providers declare typing, mandatoriness, override permissions, and status visibility. For the resolution model and how these fields interact with `valueFrom`, see [Parameters](../concepts/parameters.md).

## Fields on `TemplateParameterDefinition`

| Field | Type | Default | Purpose |
|-------|------|---------|---------|
| `type` | enum: `string`, `number`, `bool` | unset | Validate that the literal default and any instance override parse to the declared type. |
| `required` | bool | `false` | When `true`, the consuming `TemplateInstance` MUST provide a value (regardless of any `Template` default). |
| `disableOverride` | bool | `false` | When `true`, the consuming `TemplateInstance` MUST NOT supply its own value for this parameter. |
| `exposeInStatus` | bool | `false` | When `true`, the resolved value is written to `status.resolvedParameters[].value` for inspection. |

CRD-level validation rejects the conflicting combination:

```yaml
required: true, disableOverride: true   # error: cannot be both required and non-overridable
```yaml

## Example: a fully-described template parameter set

```yaml
apiVersion: templates.v2.stakater.com/v2alpha1
kind: Template
metadata:
  name: app-template
  namespace: provider
spec:
  parameters:
    - name: name
      type: string
      required: true
      exposeInStatus: true
    - name: replicas
      type: number
      value: "2"          # default
    - name: tlsEnabled
      type: bool
      value: "true"
    - name: dbPassword
      type: string
      required: true
      disableOverride: false   # implicit; explicit for clarity
    - name: imageRegistry
      type: string
      value: ghcr.io/stakater
      disableOverride: true     # consumers cannot change the registry
  gotemplate: |
    ...
```yaml

## Type checking

`type` controls how literal strings are validated:

- `string`: any value is accepted.
- `number`: must parse via `strconv.ParseFloat`. `"3"`, `"3.14"`, `"-2.5e10"` pass; `"three"` fails.
- `bool`: must parse via `strconv.ParseBool`. `"true"`/`"false"`/`"1"`/`"0"` pass; `"yes"` does not.

`objectFieldRef` may resolve to native Go types (lists, maps). When `type` is set to a scalar (`string`/`number`/`bool`), composite values are rejected: a list-valued JSONPath cannot satisfy `type: string`.

Type mismatches surface as:

```yaml
status:
  conditions:
    - type: ParametersValid
      status: "False"
      reason: InvalidParameter
      message: "parameter \"replicas\" type mismatch: expected number, got \"two\""
```yaml

## Required parameters

A `required: true` parameter:

- Has no `value` default? The `TemplateInstance` MUST override it. A missing override sets `ParametersValid=False, Reason=InvalidParameter`.
- Has a `value` default? The `TemplateInstance` MUST still override it; the default is ignored.

The intent is to force the consumer to consciously choose a value.

**Usage**: for environment-specific values such as database hostnames or TLS certificates. Avoid `required` for parameters with safe defaults.

## Locked parameters

`disableOverride: true` makes the parameter read-only from the consumer's point of view. Any `TemplateInstance` that tries to override surfaces:

```yaml
status:
  phase: Failed
  conditions:
    - type: ParametersValid
      status: "False"
      reason: OverrideNotAllowed
      message: "parameter \"imageRegistry\" cannot be overridden by this instance"
```yaml

**Usage**: for values the platform team owns, such as image registries, mandatory labels, or security-relevant settings.

## Status visibility

By default, `status.resolvedParameters[]` only records the **source** of each parameter (literal default, or which `valueFrom`). The resolved value itself is not written to status; useful when values are credentials.

Set `exposeInStatus: true` on a parameter to also record the resolved value:

```yaml
status:
  resolvedParameters:
    - name: name
      value: my-app                # exposed because exposeInStatus: true
    - name: dbPassword
      valueFrom:                   # NOT exposed
        secretKeyRef:
          name: db-credentials
          key: password
```yaml

Treat `exposeInStatus` as a public-information signal. Never set it on parameters resolved from `Secret`.

## Conditions and reasons

| Condition | Reason | When |
|-----------|--------|------|
| `ParametersValid` | `InvalidParameter` | Type mismatch on literal default; type mismatch on resolved override; missing `required` parameter; unknown parameter on instance. |
| `ParametersValid` | `OverrideNotAllowed` | Instance attempts to override a `disableOverride: true` parameter. |
| `ParametersValid` | `ParameterResolutionFailed` | A `valueFrom` source could not be resolved. |
| `ParametersValid` | `AllParametersResolved` | All parameters resolved successfully. |

## Adopting these fields incrementally

The fields are all optional with safe defaults. Adopt them incrementally:

1. Annotate each parameter with `type` first; this gives you compile-time-style validation with no behavior change.
1. Mark consumer-required values with `required: true`.
1. Mark provider-owned values with `disableOverride: true`.
1. Mark non-secret, audit-worthy values with `exposeInStatus: true`.
