# Lifecycle

Template Operator v2 owns the resources it renders. Owning them means it has to know when to clean up, when a `TemplateInstance` is deleted, when a `Template` is updated to render fewer resources, when an apply fails partway through. This page covers the machinery the operator uses to make those guarantees.

## Finalizers

Three finalizers are involved.

| Finalizer | Placed on | Purpose |
|-----------|-----------|---------|
| `templates.v2.stakater.com/finalizer` | `Template` | Blocks deletion while any `TemplateInstance` references this `Template`. |
| `templates.v2.stakater.com/template-instance` | `TemplateInstance` | Triggers the cleanup pipeline (delete every rendered resource) before the API server removes the `TemplateInstance`. |
| `templates.v2.stakater.com/template-instance-resource` | Each rendered resource | Lets the operator delete the resource cleanly even if the underlying namespace or owner reference is removed first. |

## Deletion of a Template is blocked while in use

A `Template` cannot be deleted while any `TemplateInstance` references it. The operator holds its finalizer and publishes:

```yaml
status:
  conditions:
    - type: Deleting
      status: "False"
      reason: DeletionBlocked
      message: "Template is referenced by 3 TemplateInstance(s) and cannot be deleted"
```

Delete the dependent `TemplateInstance`s first, then the `Template`.

## Ownership metadata stamped on every rendered resource

Every rendered resource is stamped with three labels that let the operator find it later, even if `status.renderedResources` is stale or lost:

| Label | Value |
|-------|-------|
| `templates.v2.stakater.com/instance-uid` | UID of the owning `TemplateInstance` |
| `templates.v2.stakater.com/instance-name` | `metadata.name` of the owning `TemplateInstance` |
| `templates.v2.stakater.com/instance-namespace` | `metadata.namespace` of the owning `TemplateInstance` |

When `sync` is enabled, an additional set of metadata is stamped for the drift webhook: see [Sync](./sync.md#ownership-metadata-used-by-sync).

## How rendered resources are applied

The operator uses server-side apply as the field manager `template-operator` and takes ownership of every field it writes. Conflicts with another field manager resolve in favor of the operator: edits made by something else are taken back the next time the operator applies. For `sync.mode: off` that happens only when the `TemplateInstance` changes; for `revert` and `strict` it happens on every reconcile.

## Updating a Template: orphan cleanup

When a `Template`'s render output shrinks or its resource names change, resources that were rendered last time but not this time become orphans. On every reconcile, the operator:

1. Validates the new render with a server-side dry run. If validation fails, the previous `status.renderedResources` is preserved unchanged and the reconcile is retried later, so nothing is lost mid-update.
1. Applies the new resources.
1. After a fully successful apply, discovers the set of resources it owns via the ownership labels (across every GVK in `status.trackedGVKs`), computes the difference against the new render, and deletes the orphans.

Failed deletes are retained in `status.renderedResources` with `status: Failed` and retried on the next reconcile. See [Orphan resource handling](../how-to-guides/orphan-resource-handling.md) for the full failure-mode catalog.

## TemplateInstance deletion

When a `TemplateInstance` enters terminating state, the operator discovers every resource it owns via the ownership labels, deletes each, and then removes its own finalizer. The label-based discovery makes deletion safe even if `status.renderedResources` is empty or stale.

## Inspecting failed cleanups

A `TemplateInstance` whose orphan deletion is retrying reports:

```yaml
status:
  phase: Ready
  renderedResources:
    - apiVersion: v1
      kind: ConfigMap
      name: leftover-config
      namespace: team-a
      status: Failed
    - apiVersion: v1
      kind: ConfigMap
      name: current-config
      namespace: team-a
```

Entries with `status: Failed` are scheduled for retry on the next reconcile. An empty `status` indicates a successfully-applied resource.

## See also

- [Status](./status.md) for what every status field means.
- [Orphan resource handling](../how-to-guides/orphan-resource-handling.md) for the full failure-mode catalog.
- [API reference: `ResourceReference`](../reference/api.md#resourcereference) and [`TemplateInstanceStatus`](../reference/api.md#templateinstancestatus).
