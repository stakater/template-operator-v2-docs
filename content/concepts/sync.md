# Sync (drift protection)

By default a `TemplateInstance` is "fire-and-forget": rendered resources are applied once, and any subsequent edit by another controller, a user, or a different operator is left alone. `Template.spec.sync` opts the `Template` into one of two stricter modes that keep the live cluster aligned with the rendered output.

## The three modes

`Template.spec.sync.mode` is `off`, `revert`, or `strict`. It defaults to `off` when `spec.sync` is omitted.

| Mode | Continuous reconcile reverts drift? | Admission webhook blocks edits? |
|------|--------------------------------------|----------------------------------|
| `off` | no | no |
| `revert` | yes | no |
| `strict` | yes | yes |

```yaml
spec:
  sync:
    mode: strict
    ignoreFields:
      - metadata.annotations
      - spec.template.spec.containers[*].env
```

## `off`: create once, then frozen

Resources are applied until the first clean pass (every resource applied, nothing left to clean up). The instance then freezes: no input change re-applies anything — not a `Template` edit, not a `TemplateInstance` edit (parameters included), not a change in a `valueFrom` source. Manual edits to the rendered resources survive, and a manually deleted resource is not recreated. The freeze start is recorded in `status.firstAppliedAt`.

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

External edits are accepted by the API server and then brought back in line with the rendered output on the next reconcile. The webhook is not involved in this mode, so the edit is not blocked at admission time, the convergence happens during the controller's normal reconcile loop.

**Usage**: for resources that may legitimately be edited from time to time (for example by a debugging engineer) but must always converge back to the rendered baseline.

## `strict`: continuous reconcile **plus** admission webhook

Everything `revert` does, plus a `ValidatingWebhookConfiguration` that intercepts UPDATE and DELETE on every resource carrying the operator's ownership label. The webhook:

- Always allows the operator's own service account through (otherwise the operator's own reverts would block themselves).
- Rejects DELETE on managed resources unless their owning `TemplateInstance` is itself being deleted.
- Rejects UPDATE if the change touches any field outside `sync.ignoreFields`.

Users get an immediate API error at admission time rather than a delayed revert.

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

## Ownership metadata used by sync

When `sync` is enabled, every rendered resource is stamped with:

| Metadata | Key | Value |
|----------|-----|-------|
| Label | `templates.v2.stakater.com/instance` | The `TemplateInstance`'s name |
| Annotation | `templates.v2.stakater.com/instance-ref` | `<namespace>/<name>` of the owning `TemplateInstance` |

The webhook keys off both. `instance-ref` lets it find the owning `TemplateInstance` (and through it, the `Template`'s sync config) without listing.

These are separate from the orphan-cleanup ownership labels (`instance-uid` / `instance-name` / `instance-namespace`) covered in [Lifecycle](./lifecycle.md).

## The `Synced` condition

A `TemplateInstance` whose `Template.spec.sync.mode` is `revert` or `strict` reports:

```yaml
status:
  conditions:
    - type: Synced
      status: "True"
      reason: SyncActive
      message: "drift watches and enforcement are active"
```

`Ready` continues to reflect overall reconciliation success. A failed drift revert surfaces through the existing `Applied=False, Reason=ApplyFailed`.

## Strict mode requires cert-manager

The webhook server needs TLS. The chart provisions:

- A self-signed `Issuer` (`selfsigned-issuer`).
- A `Certificate` for the webhook service (`webhook-server-cert`).
- A `ValidatingWebhookConfiguration` patched with the cert-manager CA bundle.

cert-manager must be installed on the cluster before you set any `Template.spec.sync.mode: strict`.

## Webhook edge cases (strict mode)

The validating webhook has two paths where it intentionally **allows** a request that you might expect it to reject. Both are unreachable through normal operation, but understanding them matters for the [security model](./security.md).

### Owning Template not found

If the webhook fires on a managed resource and finds the owning `TemplateInstance`, but the referenced `Template` is gone, the webhook allows the request. The sync mode cannot be determined without the `Template`, and denying would permanently lock the resource. This state is only reachable if the `Template`'s finalizer has been manually removed.

### Owning TemplateInstance not found

If the `templates.v2.stakater.com/instance-ref` annotation on a managed resource points at a `TemplateInstance` that no longer exists, the webhook allows the request. No owner means no enforcement is possible. Same root cause as above: a finalizer was bypassed manually, or the resource was created with an `instance-ref` pointing at a not-yet-existing `TemplateInstance` (the supported [adoption path](./lifecycle.md#opt-in-pre-stamp-the-instance-ref-annotation)).

In both cases, the controller's normal reconcile path will still surface the issue via the affected `TemplateInstance`'s status.

## Disabling sync

Setting `spec.sync.mode: off` (or removing `spec.sync` entirely) on the `Template` releases the operator's drift watches on every dependent `TemplateInstance`'s rendered resources at the next reconcile.

## See also

- [Drift protection](../how-to-guides/drift-protection.md) for choosing a mode and worked `ignoreFields` examples.
- [Lifecycle](./lifecycle.md) for the orphan-cleanup machinery sync mode interacts with.
- [API reference: `SyncConfig`](../reference/api.md#syncconfig).
