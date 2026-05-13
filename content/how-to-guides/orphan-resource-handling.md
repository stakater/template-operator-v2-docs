# Orphan Resource Handling

Examples of how the operator handles resources that were rendered last time but not this time. For the cleanup model, ownership metadata, and how failed cleanups are retried, see [Lifecycle](../concepts/lifecycle.md).

## Scenario 1: Bill shrinks a Template

Bill's `Template` originally renders a `Deployment`, a `Service`, and a `ConfigMap`. Anna's `TemplateInstance` has applied all three to `team-a`.

Bill updates the `Template` to drop the `ConfigMap`. On the next reconcile of Anna's `TemplateInstance`, the operator applies the two surviving resources and deletes the now-orphaned `ConfigMap`. Anna does not have to do anything.

## Scenario 2: a bad Template update is rejected without losing resources

If Bill ships a `Template` update whose new render is invalid (broken manifest, unknown CRD, schema error), the operator detects the problem before applying anything. The previously-rendered resources stay in place untouched, and the `TemplateInstance` reports `Phase=Failed` with a condition explaining the issue.

Once Bill fixes the `Template`, the next reconcile applies the corrected output and cleans up any orphans normally.

## Scenario 3: Anna sees a Failed cleanup in status

If the operator can't delete an orphan, for example because another controller's webhook blocks the delete, the orphan is retained in `status.renderedResources` with `status: Failed`:

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

The operator retries deletion on the next reconcile. Anna investigates the obstacle that is blocking the delete (a rejecting webhook from another operator, or a finalizer set by another controller). Once the obstacle is removed, the orphan is cleaned up automatically.

## Scenario 4: deleting a TemplateInstance

Anna deletes her `TemplateInstance`:

```bash
kubectl delete templateinstance app -n team-a
```

Every resource the `TemplateInstance` rendered is removed from the cluster before the `TemplateInstance` itself is finalized. No manual cleanup is required.

## See also

- [Lifecycle](../concepts/lifecycle.md) for the cleanup model and ownership metadata.
- [Status](../concepts/status.md) for the meaning of `status.renderedResources[].status` and `status.trackedGVKs`.
- [API reference: `ResourceReference`](../reference/api.md#resourcereference).
