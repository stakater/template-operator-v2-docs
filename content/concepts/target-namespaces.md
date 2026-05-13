# Target Namespaces

`Template.spec.targetNamespaces` is the provider's policy on which consumer namespaces are allowed to instantiate the `Template`. The provider opts namespaces in; a consumer cannot self-elect. RBAC on the provider namespace is the boundary that protects the policy itself.

## The default

When `targetNamespaces` is omitted entirely, only the `Template`'s own namespace is permitted. This is the safe default: the `Template` cannot be used by a consumer in any other namespace until the provider explicitly permits it.

## Three matching strategies

A `TemplateInstance`'s consumer namespace is permitted if **any** of these match:

1. The explicit allow-list contains the namespace name.
2. The explicit allow-list is the wildcard `["*"]`.
3. The label selector matches the consumer namespace's labels.

You can use either strategy, or both. They combine with OR semantics.

### Explicit allow-list

```yaml
spec:
  targetNamespaces:
    explicit:
      allow:
        literal:
          - team-a
          - team-b
          - team-c
```

A `TemplateInstance` is admitted iff its namespace name appears in the list.

### Wildcard

```yaml
spec:
  targetNamespaces:
    explicit:
      allow:
        literal:
          - "*"
```

`["*"]` short-circuits to "all namespaces." It's checked before any other matching.

### Label selector

```yaml
spec:
  targetNamespaces:
    selector:
      matchLabels:
        kind: tenant
```

Or with `matchExpressions`:

```yaml
spec:
  targetNamespaces:
    selector:
      matchExpressions:
        - key: stakater.com/tenant
          operator: In
          values: [alpha, beta]
        - key: stakater.com/tier
          operator: NotIn
          values: [sandbox]
```

The selector is evaluated against the consumer namespace's labels.

### Combining both

```yaml
spec:
  targetNamespaces:
    explicit:
      allow:
        literal:
          - shared-platform
    selector:
      matchLabels:
        kind: tenant
```

This permits `shared-platform` plus every namespace labelled `kind=tenant`.

## When a namespace is not permitted

The `TemplateInstance` reconcile sets:

```yaml
status:
  phase: Failed
  conditions:
    - type: TargetNamespaceAllowed
      status: "False"
      reason: NamespaceNotPermitted
      message: |
        Namespace team-x is not permitted to instantiate Template provider/foo-template.
        Check Template's targetNamespaces configuration
    - type: Ready
      status: "False"
      reason: NamespaceNotPermitted
```

The operator does not retry on a fixed interval; reconciliation is triggered when the `Template` changes, the `TemplateInstance` changes, or (in selector mode) the consumer namespace's labels change. To resolve, either widen the `Template`'s policy to include the consumer namespace, or move the `TemplateInstance` to a namespace the policy already permits.

## RBAC required

The operator's service account needs `get` on `Namespace` to read consumer-namespace labels for selector mode. This is pre-granted by the chart.

## See also

- [Target namespaces](../how-to-guides/target-namespaces.md) for examples.
- [API reference: `TargetNamespaces`](../reference/api.md#targetnamespaces).
