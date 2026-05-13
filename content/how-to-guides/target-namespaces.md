# Target Namespaces

Examples of configuring `Template.spec.targetNamespaces`. For the matching model, default behavior, and RBAC requirements, see [Target namespaces](../concepts/target-namespaces.md).

## Scenario 1: grant access to a fixed set of consumer namespaces

Bill wants `team-a`, `team-b`, and `team-c` to be able to instantiate his `app-template`. Nobody else.

```yaml
apiVersion: templates.v2.stakater.com/v2alpha1
kind: Template
metadata:
  name: app-template
  namespace: provider
spec:
  gotemplate: |
    ...
  targetNamespaces:
    explicit:
      allow:
        literal:
          - team-a
          - team-b
          - team-c
```

A `TemplateInstance` created in `team-a` is admitted; one in `team-x` is rejected with `TargetNamespaceAllowed=False, Reason=NamespaceNotPermitted`.

## Scenario 2: grant access by namespace label

Bill labels every tenant namespace with `kind: tenant` and wants the `Template` available to all of them without maintaining the explicit list.

```yaml
spec:
  targetNamespaces:
    selector:
      matchLabels:
        kind: tenant
```

The operator reads each consumer namespace's labels at admission time. Adding the label to a new namespace immediately makes it eligible; removing the label causes `TargetNamespaceAllowed` to flip to `False` on the next reconcile of any `TemplateInstance` in that namespace.

## Scenario 3: combine explicit and label-based access

Bill wants the `Template` available to every tenant namespace, plus the `shared-platform` namespace which doesn't carry the tenant label.

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

A namespace is admitted if it matches **either** rule.

## Scenario 4: open the Template to every namespace

For a `Template` that's safe to instantiate anywhere (e.g. a baseline `NetworkPolicy`), Bill uses the wildcard:

```yaml
spec:
  targetNamespaces:
    explicit:
      allow:
        literal:
          - "*"
```

The wildcard short-circuits all other matching. Use it deliberately.

## What a refusal looks like

When Anna creates a `TemplateInstance` in a non-permitted namespace, the operator publishes:

```yaml
status:
  phase: Failed
  conditions:
    - type: TargetNamespaceAllowed
      status: "False"
      reason: NamespaceNotPermitted
      message: |
        Namespace team-x is not permitted to instantiate Template provider/app-template.
        Check Template's targetNamespaces configuration
    - type: Ready
      status: "False"
      reason: NamespaceNotPermitted
```

Fixing the policy on the `Template`, or moving the `TemplateInstance` to a permitted namespace, triggers the next reconcile and clears the condition.

## See also

- [Target namespaces](../concepts/target-namespaces.md) for the matching model and RBAC.
- [API reference: `TargetNamespaces`](../reference/api.md#targetnamespaces).
