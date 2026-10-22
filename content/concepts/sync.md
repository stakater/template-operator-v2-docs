# Sync (drift protection)

By default a `TemplateInstance` is "fire-and-forget": rendered resources are applied once, and any subsequent edit by another controller, a user, or a different operator is left alone. `Template.spec.sync` opts the `Template` into one of two stricter modes that keep the live cluster aligned with the rendered output.

## The three modes

`Template.spec.sync.mode` is `off`, `revert`, or `strict`. It defaults to `off` when `spec.sync` is omitted.

| Mode | Continuous reconcile reverts drift? | Admission webhook blocks edits? |
|------|--------------------------------------|----------------------------------|
| `off` | no | no |
| `revert` | yes | no |
| `strict` | yes | yes |

The chart installs the admission webhook in every mode, and it sees every rendered resource; it denies a change when the owning `Template` uses `strict`, and in every mode when the `instance-ref` annotation is malformed or the owner lookup fails. Because the webhook uses `failurePolicy: Fail`, the API server rejects UPDATE and DELETE on rendered resources in every mode while the operator is down.

```yaml
spec:
  sync:
    mode: strict
    ignoreFields:
      - metadata.annotations
      - spec.template.spec.containers[*].env
```

## `off`: create once, then frozen

Resources are applied until the first clean pass (every resource applied, nothing left to clean up). The instance then freezes: no input change re-applies anything — not a `Template` edit, not a `TemplateInstance` edit (parameters included), not a change in a `valueFrom` source. Manual edits to the rendered resources survive. A manually deleted resource is not recreated: it stays in `Terminating`, because the operator's finalizer is not released (as under [`revert`](#revert-continuous-reconcile-no-admission-block)). The freeze start is recorded in `status.firstAppliedAt`.

To resume management, flip the `Template`'s `sync.mode` to `revert` or `strict`: the next reconcile applies the current render, and all accumulated input changes land at once (overwriting manual edits). Flipping back to `off` freezes again immediately.

Outputs stay live while frozen: the operator keeps reading the rendered resources and refreshing `status.outputs` — for example a `LoadBalancer` IP that is only assigned after the apply.

**Usage**: when other controllers or users own the resources after creation, such as an HPA scaling a `Deployment`'s `replicas`, cert-manager rotating a `Secret`'s `data`, or GitOps editing fields the operator only seeded.

### Limitation: templated output sources need `exposeInStatus`

A frozen instance resolves templated output source names (`outputs[].from.name`, `from.namespace`, `fromAll.namespace`) from `status.resolvedParameters` — the parameter values recorded at apply time — never from live values. A parameter referenced in such a template must set `exposeInStatus: true`. Without it, the value is not recorded, the source name cannot be resolved once the instance freezes, and that output fails with a condition message naming the parameter. Outputs with literal source names are unaffected.

Plan for two consequences:

- Adding `exposeInStatus: true` after the freeze does not heal the instance: values are only recorded on a full pass. Cycle the mode (`off` → `revert` → `off`) or recreate the instance.
- An exposed value is readable by anyone who can `get` the `TemplateInstance`. Do not reference a Secret-sourced parameter in an output source name: its value would appear in plain text in status — and in the resource name itself.

## `revert`: continuous reconcile, no admission block

The controller, on every reconcile of the `TemplateInstance`, re-applies the rendered output to every owned resource:

1. Fetch the live object.
1. Run a server-side dry-run apply on a copy of the desired object to fill in API-server defaults.
1. Compare the dry-run result with the live object, ignoring `ignoreFields`.
1. If they differ, apply the desired object, overwriting the drift.

External edits are accepted by the API server and then brought back in line with the rendered output on the next reconcile. The webhook does not block edits in this mode, so the edit is not blocked at admission time, the convergence happens during the controller's normal reconcile loop.

**Usage**: for resources that may legitimately be edited from time to time (for example by a debugging engineer) but must always converge back to the rendered baseline.

!!! warning "`revert` does not recover a deleted resource"
    `revert` reverts in-place *edits*, not deletions. If someone deletes a managed resource by hand, the operator's finalizer leaves it stuck in `Terminating`: the drift check compares the still-matching spec and detects no drift, so the object is never re-created, yet the finalizer is never released — and the owning `TemplateInstance` keeps reporting `Ready`. Use `strict` for resources that must not be deleted; it rejects the `DELETE` at admission instead. (Tracked upstream: a deletion under `revert` should either be reverted or surfaced on the `Synced` condition.)

## `strict`: continuous reconcile **plus** admission webhook

Everything `revert` does, plus a `ValidatingWebhookConfiguration` that intercepts UPDATE and DELETE on every resource carrying the operator's ownership label. The webhook:

- Always allows the operator's own service account through (otherwise the operator's own reverts would block themselves).
- Rejects DELETE on managed resources unless their owning `TemplateInstance` is itself being deleted.
- Rejects UPDATE if the change touches any field outside `sync.ignoreFields` and the server-managed fields. With an empty `ignoreFields` list, it rejects every UPDATE, even one that changes nothing.

Users get an immediate API error at admission time rather than a delayed revert.

The webhook is a single, **cluster-wide** `ValidatingWebhookConfiguration`, shared by every `strict` `Template`. It matches UPDATE/DELETE on all resources but narrows to managed ones with a `matchConditions` filter on the operator's ownership label, so it only evaluates objects that carry the `templates.v2.stakater.com/instance` label. The published Helm chart ships it with that filter in place; take care if you render the chart's manifests yourself, because a build of the webhook without that filter intercepts every write in the cluster.

**Usage**: for mandatory policy resources such as `NetworkPolicy`, `RoleBinding`, or image-pull `Secret`s, where edits should be impossible, not just transient.

## `ignoreFields`

`sync.ignoreFields` is a list of field paths that are **not** enforced. Changes to those paths are allowed even when sync is on.

Path syntax:

- Dot-separated: `metadata.annotations`, `spec.replicas`.
- Map keys are the literal segment after a dot.
- `[*]` expands over every element of an array; `[0]`/`[1]` target a specific index.

Common examples:

```yaml
sync:
  mode: strict
  ignoreFields:
    - metadata.annotations           # let users add their own annotations
    - metadata.labels                 # let users tag resources
    - spec.replicas                   # let HPA scale the workload
    - spec.template.spec.containers[*].env   # let env be edited
```

The operator always excludes server-managed metadata from the drift comparison even without explicit ignore entries: `resourceVersion`, `managedFields`, `generation`, `uid`, `creationTimestamp`, and `status` are never considered drift.

!!! note "`ignoreFields` does not protect a field from a re-apply"
    `ignoreFields` only controls drift detection (and, in `strict`, the webhook). When the operator re-applies a resource for another reason, it applies the full render, so a field that the template sets returns to the rendered value. For a field that another controller owns, such as `spec.replicas` under an HPA, leave the field out of the template.

## Ownership metadata used by sync

In every sync mode, every rendered resource is stamped with:

| Metadata | Key | Value |
|----------|-----|-------|
| Label | `templates.v2.stakater.com/instance` | The `TemplateInstance`'s name |
| Annotation | `templates.v2.stakater.com/instance-ref` | `<namespace>/<name>` of the owning `TemplateInstance` |

The webhook keys off both. `instance-ref` lets it find the owning `TemplateInstance` (and through it, the `Template`'s sync config) without listing.

Orphan cleanup uses the other ownership labels (`instance-uid` / `instance-name` / `instance-namespace`), covered in [Lifecycle](./lifecycle.md).

## The `Synced` condition

A `TemplateInstance` whose `Template.spec.sync.mode` is `revert` or `strict` reports:

```yaml
status:
  conditions:
    - type: Synced
      status: "True"
      reason: SyncActive
      message: "Sync is active; rendered resources are being watched for drift"
```

`Ready` continues to reflect overall reconciliation success. A failed drift revert surfaces through the existing `Applied=False, Reason=ApplyFailed`.

Under `off`, an instance reports `Synced=False` with reason `Frozen` after its first clean apply. This is the normal state, not an error.

## Webhook certificate

The webhook server needs TLS. The chart always runs the webhook, so every install needs a serving certificate, not only clusters that use `strict`. See [Installation](../installation/overview.md).

## Webhook edge cases (strict mode)

The validating webhook has two paths where it intentionally **allows** a request that you might expect it to reject. Understanding them matters for the [security model](./security.md).

### Owning Template not found

If the webhook fires on a managed resource and finds the owning `TemplateInstance`, but the referenced `Template` is gone, the webhook allows the request. The sync mode cannot be determined without the `Template`, and denying would permanently lock the resource. This state is reachable if the `Template`'s finalizer has been manually removed.

### Owning TemplateInstance not found

If the `templates.v2.stakater.com/instance-ref` annotation on a managed resource points at a `TemplateInstance` that no longer exists, the webhook allows the request. No owner means no enforcement is possible. This happens when a finalizer was bypassed manually, or when the resource was created with an `instance-ref` pointing at a not-yet-existing `TemplateInstance` (the supported [adoption path](./lifecycle.md#opt-in-pre-stamp-the-instance-ref-annotation)).

When the `Template` is missing, the `TemplateInstance` reports `TemplateResolved=False` with reason `TemplateNotFound`. When the `TemplateInstance` is missing, no status reports the resource.

## Disabling sync

Setting `spec.sync.mode: off` (or removing `spec.sync` entirely) on the `Template` releases the operator's drift watches on every dependent `TemplateInstance`'s rendered resources at the next reconcile.

## See also

- [Drift protection](../how-to-guides/drift-protection.md) for choosing a mode and worked `ignoreFields` examples.
- [Lifecycle](./lifecycle.md) for the orphan-cleanup machinery sync mode interacts with.
- [API reference: `SyncConfig`](../reference/api.md#syncconfig).
