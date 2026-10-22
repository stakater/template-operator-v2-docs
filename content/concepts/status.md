# Status

Both `Template` and `TemplateInstance` publish status that follows Kubernetes-standard conventions: a `phase`, an `observedGeneration`, and a list of `conditions[]`. The `TemplateInstance` additionally publishes its resolved parameters, the resources it rendered, and which GVKs it tracks.

Two fields summarize the operator's view of a CR:

- `status.conditions[]` carries the detailed state and is the field that automation, alerting, and other controllers should read.
- `status.phase` is a short single-word summary derived from those conditions, suitable for `kubectl get` columns and at-a-glance dashboards.

## Phase

| CR | Phase values |
|----|--------------|
| `Template` | `Valid`, `Invalid`, `Error` |
| `TemplateInstance` | `Ready`, `Failed` |

`Template` phases:

- `Valid`: spec is well-formed and (for Helm) the source is reachable and the dry-run renders cleanly.
- `Invalid`: the spec itself is broken: bad Go template syntax, a failed Go template dry run, invalid `valuesTemplate` YAML, a parameter default that does not match its `type`, or duplicate output field names.
- `Error`: Helm validation fails: source unreachable, chart or chart version not found, chart render failure, or invalid rendered YAML.

`TemplateInstance` phases:

- `Ready`: the instance rendered and applied. Conditions that report extra state, such as `OutputsResolved` or `Synced`, do not change the phase. Under `sync.mode: off`, a `Ready` instance shows `Synced=False` with reason `Frozen`; this is normal.
- `Failed`: `Ready` is `False`. At least one of `TemplateResolved`, `TargetNamespaceAllowed`, `ParametersValid`, `Rendered`, or `Applied` is `False`, an orphan could not be disposed of (`Ready` reason `DisposalFailed`), or cleanup during deletion failed (`Ready` reason `DeletionBlocked`).

## ObservedGeneration

Both CRs publish `status.observedGeneration` after a successful reconcile. Use it to tell whether the controller has caught up with the latest spec change:

```bash
kubectl get template my-template -o jsonpath='{.metadata.generation}/{.status.observedGeneration}'
```

When the two differ, a reconcile is pending or in progress, or the last reconcile failed; check `phase` and `conditions`.

## Conditions

Each entry follows the standard Kubernetes condition shape: `Type`, `Status` (`True`/`False`/`Unknown`), `Reason`, `Message`, `LastTransitionTime`, `ObservedGeneration`.

### Template conditions

| Type | Status | Reason | Meaning |
|------|--------|--------|---------|
| `Valid` | `True` | `ValidationSucceeded` | Spec parsed and validated successfully. |
| `Valid` | `False` | `ValidationFailed` | A render-time validation check failed. |
| `ParametersValid` | `True` | `AllParametersResolved` | Every parameter default matches its declared `type`. |
| `ParametersValid` | `False` | `InvalidParameter` | A parameter default does not match its declared `type`. |
| `SourceAccessible` | `True` | `RepositoryReachable` | Helm chart was pulled successfully. |
| `SourceAccessible` | `False` | `RepositoryUnreachable` | Helm chart could not be pulled from the configured repository. |
| `SourceAccessible` | `False` | `ValidationFailed` | Skipped because the `valuesTemplate` is invalid. |
| `DryRunRendered` | `True` | `RenderSucceeded` | Template rendered to valid YAML with dummy parameters. |
| `DryRunRendered` | `False` | `RenderFailed` | Rendering or YAML validation failed during the dry run. |
| `DryRunRendered` | `False` | `DryRunSkipped` | The `Template` has at least one dynamic parameter, so a dry run with dummy values would not be representative. End-to-end validation happens when the first `TemplateInstance` references it. |
| `DryRunRendered` | `False` | `ValidationFailed` | Skipped because the `valuesTemplate` is invalid. |
| `EnforcementActive` | `True` | `WebhookActive` | (`sync.mode: strict` only.) A `ValidatingWebhookConfiguration` carries the sync-enforcement webhook. |
| `EnforcementActive` | `False` | `WebhookInactive` | (`strict` only.) The operator runs without `--enable-webhooks`, or no `ValidatingWebhookConfiguration` carries the sync-enforcement webhook; protection degrades to `revert`. |
| `EnforcementActive` | `Unknown` | `WebhookStateUnknown` | (`strict` only.) The operator could not list the webhook configurations. |
| `Deleting` | `False` | `DeletionBlocked` | A `TemplateInstance` still references this `Template`, so the finalizer is held and deletion is blocked. |

### TemplateInstance conditions

| Type | Status | Reason | Meaning |
|------|--------|--------|---------|
| `TemplateResolved` | `True` | `Success` | The referenced `Template` was found. |
| `TemplateResolved` | `False` | `TemplateNotFound` | `spec.templateRef` does not resolve to an existing `Template`. |
| `TargetNamespaceAllowed` | `True` | `Success` | The consumer namespace is permitted by the `Template`'s `targetNamespaces` policy. |
| `TargetNamespaceAllowed` | `False` | `NamespaceNotPermitted` | The consumer namespace is not permitted by the `Template`'s `targetNamespaces` policy. |
| `ParametersValid` | `True` | `AllParametersResolved` | Every parameter resolved, type-validated, and (where applicable) was authorized to override. |
| `ParametersValid` | `False` | `ParameterResolutionFailed` | A `valueFrom` source could not be resolved (missing resource, missing key, JSONPath error, etc.). |
| `ParametersValid` | `False` | `InvalidParameter` | A `type` mismatch, a missing `required` value, or an unknown parameter on the `TemplateInstance`. |
| `ParametersValid` | `False` | `OverrideNotAllowed` | The `TemplateInstance` attempted to override a parameter declared with `disableOverride: true`. |
| `ParametersValid` | `False` | `ParameterAccessDenied` | The resolving identity may not read a `valueFrom` source, and the parameter has no `defaultValue`. |
| `ParametersValid` | `False` | `NamespaceSelectorMatchedZero` | A `namespaceSelector` matched no namespaces, and the parameter has no `defaultValue`. |
| `ParametersValid` | `False` | `ServiceAccountNotFound` | The `ServiceAccount` named by `spec.serviceAccountRef` does not exist. |
| `ParametersValid` | `False` | `ImpersonationNotPermitted` | The operator may not impersonate the `ServiceAccount` named by `spec.serviceAccountRef`. |
| `Rendered` | `True` | `Success` | The template body produced parseable YAML. |
| `Rendered` | `False` | `TemplateExecutionFailed` | Template execution returned an error or its output was not valid YAML. |
| `Applied` | `True` | `Success` | Every rendered resource was applied. |
| `Applied` | `False` | `ApplyFailed` | At least one apply was rejected by the API server. |
| `Applied` | `False` | `InvalidDeletionPolicy` | A rendered resource has a `deletion-policy` value other than `Delete` or `Orphan`; nothing was applied. |
| `Synced` | `True` | `SyncActive` | (`sync.mode != off` only.) Drift watches on the rendered resources are active. For `strict`, the `Template`'s `EnforcementActive` condition reports whether the webhook is installed. |
| `Synced` | `False` | `SyncActive` | (`sync.mode != off` only.) The drift watches could not be set up. |
| `Synced` | `False` | `Frozen` | (`sync.mode: off` only.) The instance is frozen after its first clean apply. |
| `OutputsResolved` | `True` | `OutputsResolved` | Every declared output field resolved. |
| `OutputsResolved` | `False` | `OutputResolutionFailed` | At least one output field did not resolve. |
| `OutputsResolved` | `False` | `OutputsWatchFailed` | The watch on the output sources could not be set up, so the values may not refresh. |
| `ParameterWatchesActive` | `True` | `WatchesActive` | The `valueFrom` sources are watched for changes. |
| `ParameterWatchesActive` | `False` | `WatchesPending` | The parameter watches have not synced yet. |
| `ParameterWatchesActive` | `False` | `WatchesInactive` | The parameter watches do not deliver; values refresh only on the periodic re-check. |
| `Ready` | `True` | `Reconciled` | `TemplateResolved`, `TargetNamespaceAllowed`, `ParametersValid`, `Rendered`, and `Applied` are `True`, and no orphan disposal failed. |
| `Ready` | `False` | (propagated) | The first failing condition's reason is copied here, so callers can rely on a single field to detect failure. |
| `Ready` | `False` | `DisposalFailed` | An orphaned resource could not be deleted or released; the operator retries. |
| `Ready` | `False` | `DeletionBlocked` | The `TemplateInstance` is being deleted and a rendered resource could not be disposed of; the operator retries. |

## ResolvedTemplateRef

`status.resolvedTemplateRef` records the exact `Template` that was rendered, including its generation:

```yaml
status:
  resolvedTemplateRef:
    name: foo-template
    namespace: foo
    generation: 5
```

The `generation` is useful for telling whether a `TemplateInstance` was rendered against the latest spec of the referenced `Template`, or an older one.

## ResolvedParameters

`status.resolvedParameters[]` records the **source** of each parameter after merging:

```yaml
status:
  resolvedParameters:
    - name: replicas                     # used Template default
    - name: dbPassword
      valueFrom:                          # resolved from a Secret
        secretKeyRef:
          name: db-credentials
          key: password
    - name: ingressIP
      valueFrom:
        objectFieldRef:
          apiVersion: networking.k8s.io/v1
          kind: Ingress
          name: my-ingress
          namespace: team-a
          jsonPath: .status.loadBalancer.ingress[0].ip
```

The resolved value itself is **not** written to status by default. Set [`exposeInStatus: true`](./parameters.md#exposeinstatus-semantics) on a parameter definition to also record the value:

```yaml
status:
  resolvedParameters:
    - name: name
      value: my-app                       # exposed because exposeInStatus: true
```

Hiding values by default is deliberate, since parameters resolved from a `Secret` may carry credentials. Set `exposeInStatus: true` only on parameters whose resolved values are safe to publish, such as audit-relevant configuration.

## RenderedResources

`status.renderedResources[]` lists the resources the operator owns for this `TemplateInstance`. Each entry has the minimum information needed to find and delete the resource later.

```yaml
status:
  renderedResources:
    - apiVersion: v1
      kind: Pod
      name: my-custom-pod
      namespace: team-a
      observedGeneration: 1               # the rendered resource's own metadata.generation
    - apiVersion: v1
      kind: ConfigMap
      name: leftover-config
      namespace: team-a
      status: Failed                       # operator hit an error on this resource and will retry
```

| Field | Purpose |
|-------|---------|
| `apiVersion`, `kind`, `name`, `namespace` | Identity tuple used as the key. |
| `observedGeneration` | The rendered resource's `metadata.generation` at the time of last successful apply. |
| `status` | `""` (successfully applied) or `"Failed"` (operator will retry on the next reconcile). |

This list can hold a maximum of 500 entries. It is the operator's cleanup index for resources owned by this `TemplateInstance`, not a cache of those resources' desired or live state. The `status` field is excluded from identity comparison, so a previously-failed entry is matched against the new render output rather than being treated as a separate orphan.

## TrackedGVKs

`status.trackedGVKs[]` is the set of GroupVersionKinds this `TemplateInstance` has ever rendered, formatted `<group>/<version>/<kind>`:

```yaml
status:
  trackedGVKs:
    - /v1/ConfigMap                       # core group
    - apps/v1/Deployment
    - networking.k8s.io/v1/Ingress
```

`status.trackedGVKs` is persisted **before** the main render/apply cycle. This way, even if `status.renderedResources` is wiped or becomes stale, the operator still knows which GVKs to list when discovering owned resources via the ownership labels. See [Lifecycle](./lifecycle.md) for how that recovery path works.

## Putting it together

A healthy reconcile reports:

```yaml
status:
  phase: Ready
  observedGeneration: 3
  resolvedTemplateRef:
    name: foo-template
    namespace: foo
    generation: 5
  resolvedParameters: [...]
  renderedResources: [...]
  trackedGVKs: [...]
  conditions:
    - { type: TemplateResolved,    status: "True", reason: Success }
    - { type: TargetNamespaceAllowed, status: "True", reason: Success }
    - { type: ParametersValid,     status: "True", reason: AllParametersResolved }
    - { type: Rendered,             status: "True", reason: Success }
    - { type: Applied,              status: "True", reason: Success }
    - { type: Synced,               status: "False", reason: Frozen }   # revert/strict: "True", SyncActive
    - { type: Ready,                status: "True", reason: Reconciled }
```

## See also

- [Outputs](./outputs.md) for `status.outputs` and the `OutputsResolved` condition.
- [Troubleshooting](../troubleshooting.md) maps common failure conditions to fixes.
- [API reference: `TemplateStatus`](../reference/api.md#templatestatus) and [`TemplateInstanceStatus`](../reference/api.md#templateinstancestatus).
