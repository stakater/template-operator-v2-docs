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
- `Invalid`: the spec itself is broken: bad Go template syntax, invalid `valuesTemplate` YAML, invalid `helm.chart.repository.version`.
- `Error`: an external system fails: Helm source unreachable, chart download failure.

`TemplateInstance` phases:

- `Ready`: all conditions are true.
- `Failed`: at least one of `TemplateResolved`, `TargetNamespaceAllowed`, `ParametersValid`, `Rendered`, or `Applied` is `False`.

## ObservedGeneration

Both CRs publish `status.observedGeneration` after a successful reconcile. Use it to tell whether the controller has caught up with the latest spec change:

```bash
kubectl get template my-template -o jsonpath='{.metadata.generation}/{.status.observedGeneration}'
```

When the two differ, a reconcile is pending or in progress.

## Conditions

Each entry follows the standard Kubernetes condition shape: `Type`, `Status` (`True`/`False`/`Unknown`), `Reason`, `Message`, `LastTransitionTime`, `ObservedGeneration`.

### Template conditions

| Type | Status | Reason | Meaning |
|------|--------|--------|---------|
| `Valid` | `True` | `ValidationSucceeded` | Spec parsed and validated successfully. |
| `Valid` | `False` | `ValidationFailed` | A render-time validation check failed. |
| `Valid` | `False` | `SpecInvalid` | The spec is structurally invalid. |
| `SourceAccessible` | `True` | `RepositoryReachable` | Helm chart was pulled successfully. |
| `SourceAccessible` | `False` | `RepositoryUnreachable` | Helm chart could not be pulled from the configured repository. |
| `DryRunRendered` | `True` | `RenderSucceeded` | Template rendered to valid YAML with dummy parameters. |
| `DryRunRendered` | `False` | `RenderFailed` | Rendering or YAML validation failed during the dry run. |
| `DryRunRendered` | `False` | `DryRunSkipped` | The `Template` has at least one dynamic parameter, so a dry run with dummy values would not be representative. End-to-end validation happens when the first `TemplateInstance` references it. |
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
| `Rendered` | `True` | `Success` | The template body produced parseable YAML. |
| `Rendered` | `False` | `TemplateExecutionFailed` | Template execution returned an error or its output was not valid YAML. |
| `Applied` | `True` | `Success` | Every rendered resource was applied. |
| `Applied` | `False` | `ApplyFailed` | At least one apply was rejected by the API server. |
| `Synced` | `True` | `SyncActive` | (`sync.mode != off` only.) Drift watches and, for `strict`, webhook enforcement are active. |
| `Ready` | `True` | `Reconciled` | All preceding conditions are `True`. |
| `Ready` | `False` | (propagated) | The first failing condition's reason is copied here, so callers can rely on a single field to detect failure. |

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
    - { type: Ready,                status: "True", reason: Reconciled }
```

## See also

- [Troubleshooting](../troubleshooting.md) maps common failure conditions to fixes.
- [API reference: `TemplateStatus`](../reference/api.md#templatestatus) and [`TemplateInstanceStatus`](../reference/api.md#templateinstancestatus).
