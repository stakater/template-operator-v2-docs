# Outputs

`Template.spec.outputs` declares named extractions from the resources a `TemplateInstance` renders, surfaced on `TemplateInstance.status.outputs`. It lets a consumer read back a value the rendered resource only gets at runtime — an allocated IP, a downstream controller's status, a generated name — without querying those resources directly.

## Each output chooses one iteration mode

Every entry in `outputs[]` has a `name` (the parent identifier, unique across `outputs[]`) and exactly one iteration mode, chosen by which fields are set:

| Mode | Fields set | What it extracts |
|------|------------|------------------|
| Single | `from` only | one rendered resource |
| All of a kind | `fromAll` only | every rendered resource matching the GVK |
| Array within one | `from` + `forEach` | each object in an array inside one rendered resource |

Each mode then lists one or more `fields` to pull out.

## Fields

```yaml
outputs:
  - name: service
    from:
      apiVersion: v1
      kind: Service
      name: "{.parameters.name}"       # JSONPath template over the Template context
    fields:
      - name: clusterIP                 # the OUTER key under status.outputs
        jsonPath: "{.spec.clusterIP}"
```

- `fields[].name` is the **outer key** under `status.outputs`. It must be unique across the flattened set of every `fields[].name` in the `Template`.
- `fields[].jsonPath` is a JSONPath query wrapped in `{...}`. A scalar result is stored as-is; an array or object result is JSON-encoded — `"{.status.loadBalancer.ingress[*].ip}"` becomes `'["10.0.0.1","10.0.0.2"]'`.

The result lands at `status.outputs.<output-name>.<field-name>`.

## `from`: a single resource

`from` selects one rendered resource by GVK and `name` (a JSONPath template evaluated against the Template context — `{"parameters": {...}, "instance": {name, namespace, labels}}`). `namespace` is also a JSONPath template and defaults to the `TemplateInstance`'s namespace. The named resource must exist in `status.renderedResources` at extraction time.

## `fromAll`: every resource of a kind

`fromAll` iterates every rendered resource matching the GVK, and `keyTemplate` renders the inner map key so each resource gets its own entry:

```yaml
outputs:
  - name: deployments
    fromAll:
      apiVersion: apps/v1
      kind: Deployment
    keyTemplate: "{.metadata.namespace}/{.metadata.name}"
    fields:
      - name: available
        jsonPath: "{.status.availableReplicas}"
```

gives:

```yaml
status:
  outputs:
    deployments:
      team-a/web: { available: "3" }
      team-a/worker: { available: "1" }
```

`keyTemplate` is optional for `fromAll` (it defaults to `{.metadata.namespace}/{.metadata.name}` for namespaced kinds and `{.metadata.name}` for cluster-scoped), and optional for single mode (defaults to `{.metadata.name}`).

This is the pattern a provider uses to answer "is every rendered resource healthy?" from one object — for example aggregating the status of child resources a parent `TemplateInstance` emits.

## `forEach`: an array inside one resource

`from` + `forEach` iterates an array **of objects** inside the resource named by `from`. `forEach` is a JSONPath query wrapped in `{...}`, and `keyTemplate` (required here) builds each entry's key — `{.__index}` (the zero-based position) is available to it alongside the object's own fields.

## The `OutputsResolved` condition

Resolution is reported on the `TemplateInstance`'s `OutputsResolved` condition. A field whose JSONPath matches nothing, or whose source resource is absent, leaves that entry unresolved and is reflected there rather than failing the whole instance. See [Status](./status.md#conditions).

## `Kind: Secret` is refused

A `Secret` may not be an output source — `from.kind: Secret` and `fromAll.kind: Secret` are refused at admission, so a `Secret`'s contents cannot be copied into status. Resolve secret material through [`valueFrom.secretKeyRef`](./parameters.md) instead, and never with `exposeInStatus`.

## See also

- [Status](./status.md) for where outputs appear and the `OutputsResolved` condition.
- [Parameters](./parameters.md) for the Template context that `name`/`namespace` templates evaluate against.
- [API reference: `TemplateSpec`](../reference/api.md#templatespec).
