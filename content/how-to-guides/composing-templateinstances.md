# Composing TemplateInstances

A `Template` can render **`TemplateInstance`s** — a parent that fans out to one child instance per item, where each child renders the real resources. This is the pattern platform integrations are built on: it gives every item its own status, isolates failures, and keeps the watch count flat.

## When to reach for it

[Rendering to many namespaces](./rendering-to-many-namespaces.md) emits the target resources directly from one instance. Prefer **composition** instead when you want, per item:

- **its own status** — each child `TemplateInstance` reports its own conditions, so you can see which item failed;
- **failure isolation** — a malformed render for one item fails only that child, not the whole fan-out;
- **a bounded, shared watch** — the parent holds one cluster-wide watch regardless of how many children it emits.

## The two Templates

The **child** renders the actual resource for one item, from parameters:

```yaml
apiVersion: templates.v2.stakater.com/v2alpha1
kind: Template
metadata:
  name: namespace-quota-child
  namespace: provider
spec:
  parameters:
    - name: namespace
      required: true
  gotemplate: |
    apiVersion: v1
    kind: ResourceQuota
    metadata:
      name: default-quota
      namespace: {{ .parameters.namespace }}
    spec:
      hard:
        pods: "20"
  sync:
    mode: strict
```

The **parent** lists namespaces and emits one child `TemplateInstance` per match. Child instances live in the `provider` namespace; the child `Template`'s default [`targetNamespaces`](../concepts/target-namespaces.md) (its own namespace) already allows that.

```yaml
apiVersion: templates.v2.stakater.com/v2alpha1
kind: Template
metadata:
  name: namespace-quota-parent
  namespace: provider
spec:
  parameters:
    - name: namespaces
      required: true
  gotemplate: |
    {{- range $ns := .parameters.namespaces }}
    {{- if hasKey (default dict $ns.metadata.labels) "team" }}
    ---
    apiVersion: templates.v2.stakater.com/v2alpha1
    kind: TemplateInstance
    metadata:
      name: quota-{{ $ns.metadata.name }}
      namespace: provider
    spec:
      templateRef:
        name: namespace-quota-child
        namespace: provider
      parameters:
        - name: namespace
          value: {{ $ns.metadata.name | quote }}
    {{- end }}
    {{- end }}
  outputs:
    - name: children
      fromAll:
        apiVersion: templates.v2.stakater.com/v2alpha1
        kind: TemplateInstance
        namespace: provider
      keyTemplate: "{.metadata.name}"
      fields:
        - name: ready
          jsonPath: "{.status.conditions[?(@.type=='Ready')].status}"
  sync:
    mode: revert
```

Bind the parent with a LIST of namespaces, exactly as in [the fan-out guide](./rendering-to-many-namespaces.md#2-bind-it-listing-all-namespaces). The operator creates a child `TemplateInstance` per `team` namespace, each of which renders its `ResourceQuota`.

## One place to read health

The parent's [`outputs`](../concepts/outputs.md) aggregate every child's `Ready` condition, so a single object answers "is every item reconciled?":

```bash
kubectl get templateinstance namespace-quota-parent -n provider \
  -o jsonpath='{.status.outputs.children}' | jq .
# { "quota-team-a": { "ready": "True" }, "quota-team-b": { "ready": "True" } }
```

## Naming

A child's name is composed from the item (`quota-<namespace>`). Choose a prefix the parent's own name can never take, so a crafted item value cannot produce a child that collides with the parent instance.

## See also

- [Rendering to many namespaces](./rendering-to-many-namespaces.md) — the simpler, direct fan-out.
- [Outputs](../concepts/outputs.md) — aggregating child status with `fromAll`.
- [Lifecycle](../concepts/lifecycle.md) — how the operator cleans up children when the parent stops emitting them.
