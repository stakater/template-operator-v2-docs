# Orphan Resource Handling

Examples of how the operator handles resources that were rendered last time but not this time. For the cleanup model, ownership metadata, and how failed cleanups are retried, see [Lifecycle](../concepts/lifecycle.md).

## Scenario 1: Bill shrinks a Template

Bill's `Template` originally renders a `Deployment`, a `Service`, and a `ConfigMap`. Anna's `TemplateInstance` has applied all three to `team-a`.

Bill updates the `Template` to drop the `ConfigMap`. With `sync.mode: revert` or `strict`, on the next reconcile of Anna's `TemplateInstance`, the operator applies the two surviving resources and deletes the now-orphaned `ConfigMap`, unless it carries `templates.v2.stakater.com/deletion-policy: Orphan` (or `helm.sh/resource-policy: keep`); the operator then releases it and leaves it in place. Anna does not have to do anything.

Under the default `sync.mode: off`, the instance is frozen after its first clean apply, so the `ConfigMap` stays until the mode changes.

## Scenario 2: a bad Template update is rejected without losing resources

With `sync.mode: revert` or `strict`, if Bill ships a `Template` update whose new render is invalid (broken manifest, unknown CRD, schema error), the operator detects the problem before applying anything. The previously-rendered resources stay in place untouched, and the `TemplateInstance` reports `Phase=Failed` with a condition explaining the issue.

Once Bill fixes the `Template`, the next reconcile applies the corrected output and cleans up any orphans normally.

Under the default `sync.mode: off`, the instance is frozen after its first clean apply, so it does not see the bad update or the fix and stays `Ready`.

## Scenario 3: Anna sees a Failed cleanup in status

If the operator can't delete an orphan, for example because another controller's webhook blocks the delete, the orphan is retained in `status.renderedResources` with `status: Failed`:

```yaml
status:
  phase: Failed
  conditions:
    - type: Ready
      status: "False"
      reason: DisposalFailed
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

The operator retries deletion on the next reconcile. Anna investigates the obstacle that is blocking the delete, for example a rejecting webhook from another operator. Once the obstacle is removed, the orphan is cleaned up automatically. A finalizer from another controller does not block cleanup: the operator treats the delete as done, and the object stays `Terminating` until that controller removes its finalizer.

## Scenario 4: deleting a TemplateInstance

Anna deletes her `TemplateInstance`:

```bash
kubectl delete templateinstance app -n team-a
```

Every resource the `TemplateInstance` rendered is removed from the cluster before the `TemplateInstance` itself is finalized, unless it carries `templates.v2.stakater.com/deletion-policy: Orphan` (or `helm.sh/resource-policy: keep`); the operator then releases it and leaves it in place. No manual cleanup is required.

## See also

- [Lifecycle](../concepts/lifecycle.md) for the cleanup model and ownership metadata.
- [Status](../concepts/status.md) for the meaning of `status.renderedResources[].status` and `status.trackedGVKs`.
- [API reference: `ResourceReference`](../reference/api.md#resourcereference).
