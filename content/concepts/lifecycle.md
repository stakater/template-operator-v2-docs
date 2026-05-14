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

## Resource adoption

A rendered resource is considered "owned" if it carries the operator's ownership labels and the `templates.v2.stakater.com/template-instance-resource` finalizer. Adoption is the process of taking an existing in-cluster resource and giving it those marks, so that the operator manages it from that point on.

There are two paths into adoption.

### Opt-in: pre-stamp the `instance-ref` annotation

Before the `TemplateInstance` exists, an admin can create a resource manually and annotate it with `templates.v2.stakater.com/instance-ref: <namespace>/<name>` pointing at the `TemplateInstance` they intend to create later. The drift webhook intercepts UPDATE and DELETE only, so the resource is admitted at CREATE time. When the named `TemplateInstance` is eventually created and its render targets the same `apiVersion`/`kind`/`name`/`namespace`, the operator picks the resource up and treats it as one of its rendered outputs.

This is the supported migration path for moving an existing in-cluster resource under operator management without deleting and re-creating it.

### Implicit: name collision during apply

!!! warning "Name collisions silently take over existing resources"
    The operator applies rendered resources with server-side apply and `ForceOwnership=true`. If a `Template` renders a resource whose `apiVersion`/`kind`/`namespace`/`name` matches an existing in-cluster resource, even one the operator did not create, the existing resource is silently adopted in place.

What "adopted in place" means:

- The resource's UID and `creationTimestamp` are preserved (it is mutated, not recreated).
- The operator stamps it with the ownership labels, the `instance-ref` annotation, and the rendered-resource finalizer.
- Fields written by the template are taken over from whatever field manager owned them previously.
- Deleting the `TemplateInstance` will cascade-delete the adopted resource, even though the operator never created it.

Mitigation:

- Treat the rendered name set as a global namespace within each target namespace. A typo or a Template that reuses a common name (`config`, `app`, `tls`) can silently capture an unrelated resource.
- Use a naming convention that includes the `TemplateInstance` name (for example `{{ .instance.name }}-config`) so collisions are accidental rather than routine.
- Before applying a new `Template`, verify no resources of the same `apiVersion`/`kind`/`name`/`namespace` already exist in the consumer namespace.

See also [Security model](./security.md) for the broader trust boundaries.

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
