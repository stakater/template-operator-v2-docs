# Troubleshooting

When a `Template` or `TemplateInstance` isn't behaving as expected, start by reading its `status`. The operator records every failure as a condition with a specific `reason`, and the sections below are indexed by that reason. Each entry names the cause and the action that resolves it.

For the full catalogue of conditions and what each one means, see [Status](./concepts/status.md).

## Where to start

When something isn't working:

1. **Read `status.phase`** with `kubectl get`. `Valid`/`Ready` means the operator is happy. `Invalid`, `Error`, or `Failed` means there's something to fix.
1. **Read `status.conditions[]`** with `kubectl describe` or `kubectl get -o yaml`. Find the first condition with `status: False`. Its `reason` field is the key to the entry below.
1. **Look up that reason** in the section for your CR (`Template` or `TemplateInstance`).
1. **If nothing matches**, drop to [Operational](#operational) for issues that don't show up in `status`, or check the controller logs.

## Gathering information

```bash
# Status, conditions, and the rendered-resources list
kubectl describe template <name> -n <provider-namespace>
kubectl describe templateinstance <name> -n <consumer-namespace>

# Events for the CR (often shows the underlying error)
kubectl get events -n <namespace> --field-selector involvedObject.name=<name>

# Controller logs
kubectl logs -n template-operator-system deploy/controller-manager

# Resources owned by a TemplateInstance (across all GVKs)
kubectl get <kind> -A -l templates.v2.stakater.com/instance-uid=<uid>
```

The instance UID is in `kubectl get templateinstance <name> -o jsonpath='{.metadata.uid}'`.

## Template

### `Valid=False, Reason=ValidationFailed` or `SpecInvalid`

**Cause**: `spec.gotemplate` or `spec.helm.valuesTemplate` failed to parse, or a structural invariant was violated. The `Message` quotes the parser error.

**Resolution**: correct the syntax in the named field.

### `DryRunRendered=False, Reason=RenderFailed`

**Cause**: the template parses but executing it with dummy values produces invalid YAML. Common culprits are missing whitespace inside `{{ }}`, a `range` or `if` that emits a fragment outside any document, or an unquoted string containing `:`.

**Resolution**: render the template locally with `helm template` (for Helm) or `gomplate` (for Go templates) using the same `.parameters` / `.instance` shape, and inspect the output.

### `DryRunRendered=False, Reason=DryRunSkipped`

**Cause**: at least one parameter has no literal default, so a dry run with dummy values would not be representative. This is informational, not an error.

**Resolution**: none. The `Template` is `Valid` overall; end-to-end validation happens when the first `TemplateInstance` references it.

### `SourceAccessible=False, Reason=RepositoryUnreachable`

**Cause**: the Helm chart could not be pulled. The `Message` quotes the underlying error.

**Resolution**: check each of these in turn:

- `spec.helm.chart.repository.url` matches `^(https?|oci)://`.
- `spec.helm.chart.repository.version` follows SemVer 2 (`MAJOR.MINOR.PATCH`). Ranges and `latest` are rejected.
- For private repositories, `auth.secretRef` is set and the `Secret` lives in the same namespace as the `Template`.
- The auth `Secret` carries the right keys: `username` + `password` (for basic auth and token-based registries, where the token goes in `password`), or `.dockerconfigjson` (for OCI registries with a docker config).

The reconcile retries every 60 seconds, so transient registry outages self-heal.

### `Deleting=False, Reason=DeletionBlocked`

**Cause**: a `TemplateInstance` still references this `Template`. The operator holds the finalizer until those instances are gone.

**Resolution**: list the dependent instances, delete them first, then re-run `kubectl delete template`:

```bash
kubectl get templateinstances -A \
  -o jsonpath='{range .items[?(@.spec.templateRef.name=="<template-name>")]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}'
```

## TemplateInstance

### `TemplateResolved=False, Reason=TemplateNotFound`

**Cause**: `spec.templateRef` doesn't point to an existing `Template`.

**Resolution**: confirm name, namespace, and that the `Template` is applied. The reconcile retries every 30 seconds, so creating the missing `Template` fixes the instance automatically.

### `TargetNamespaceAllowed=False, Reason=NamespaceNotPermitted`

**Cause**: the consumer namespace is not in `Template.spec.targetNamespaces`.

**Resolution**: either widen the `Template`'s policy (add to `explicit.allow.literal`, or apply a matching label to the consumer namespace), or move the `TemplateInstance` to a permitted namespace. The operator re-reconciles when the `Template`, the `TemplateInstance`, or the namespace's labels change.

### `ParametersValid=False, Reason=ParameterResolutionFailed`

**Cause**: a `valueFrom` source could not be resolved. Common per source:

- `secretKeyRef` / `configMapKeyRef`: the resource doesn't exist, or the `key` is missing.
- `objectFieldRef` (GET): the named resource doesn't exist, or the JSONPath matched nothing.
- `objectFieldRef` (LIST): no resources of that GVK exist in the targeted namespace(s), or the GVK isn't registered.

**Resolution**: create the missing source. For optional sources, set `defaultValue` alongside `valueFrom` so the resolution falls back instead of failing.

### `ParametersValid=False, Reason=InvalidParameter`

**Cause**: a parameter failed type validation, a `required: true` parameter was not overridden, or the `TemplateInstance` referenced a parameter name that isn't declared on the `Template`. The `Message` identifies the offending parameter.

**Resolution**: supply a value that matches the parameter's declared `type`, override every `required: true` parameter, and only reference declared parameter names.

### `ParametersValid=False, Reason=OverrideNotAllowed`

**Cause**: the `TemplateInstance` tried to override a parameter declared with `disableOverride: true`.

**Resolution**: remove the override from the `TemplateInstance`. If per-instance values are genuinely needed, the platform team should remove `disableOverride: true` on the `Template`.

### `Rendered=False, Reason=TemplateExecutionFailed`

**Cause**: the template parses but executing it with the resolved parameters fails. Common: a `nil` map access in the Go template, or `valuesTemplate` output that isn't a YAML mapping at the top level.

**Resolution**: inspect the `Message`. Add guards for optional values (e.g. `{{ if .parameters.foo }}`) and confirm `valuesTemplate` renders to a mapping.

### `Applied=False, Reason=ApplyFailed`

**Cause**: the API server rejected at least one of the rendered manifests. The `Message` quotes the apply error: schema validation, RBAC, or admission webhooks from other operators.

**Resolution**: read the conditions, correct the rendered output (usually by editing the `Template`), and the next reconcile applies cleanly.

## Drift protection

### A legitimate edit is rejected in `strict` mode

**Cause**: the validating webhook rejects UPDATE/DELETE on managed resources except for the operator itself and for fields listed in `sync.ignoreFields`.

**Resolution**: add the field path to `sync.ignoreFields` on the `Template`. The next reconcile updates the webhook's view.

### `Synced` condition is missing

**Cause**: `Synced` is only published when `Template.spec.sync.mode` is `revert` or `strict`. If you expect drift protection and don't see it, the mode is `off`.

**Resolution**: set `spec.sync.mode` to `revert` or `strict` on the `Template`. For `strict`, cert-manager must be installed on the cluster, since the webhook needs TLS.

### External edits keep being reverted in `revert` mode

This is the intended behavior. The operator re-applies the rendered output on every reconcile.

**Resolution**: if a field should be edited freely, add it to `sync.ignoreFields`.

## Operational

### Stuck reconcile or status not updating

**Cause**: the controller has stopped progressing, or is repeatedly hitting the same error.

**Resolution**: compare `status.observedGeneration` to `metadata.generation`. If they don't converge, check the controller logs for repeated `failed to ...` errors with the same text. `Failed to set up parameter watches` is non-fatal but means external changes to that source won't trigger re-reconciliation.

### Render uses stale parameter values

**Cause**: a `Secret` or `ConfigMap` change isn't being picked up.

**Resolution**: confirm the operator's RBAC includes `get`/`list`/`watch` on the GVK in the relevant namespace. For an `objectFieldRef` on a CRD, confirm the CRD is installed. To force an immediate reconcile:

```bash
kubectl annotate templateinstance <name> -n <namespace> \
  reconcile.stakater.com/timestamp="$(date -Iseconds)" --overwrite
```

### Failed orphan stuck in `status.renderedResources`

**Cause**: a previously-rendered resource cannot be deleted. Most commonly another operator's webhook or finalizer is blocking the delete.

**Resolution**: inspect the resource's finalizers and any blocking admission webhooks. The operator retries deletion automatically once the obstacle is removed.

### `TemplateInstance` stuck terminating

**Cause**: the operator can't delete one or more rendered resources. The controller logs name the resource.

**Resolution**: clear the underlying obstacle (a finalizer or rejecting webhook on the rendered resource), then the operator finishes the cleanup. If you must recover manually, see [Recovery procedures](#recovery-procedures).

## Recovery procedures

### Force an immediate reconcile

```bash
kubectl annotate templateinstance <name> -n <namespace> \
  reconcile.stakater.com/timestamp="$(date -Iseconds)" --overwrite
```

Annotation changes are part of the controller's predicate set, so this re-enqueues the instance without changing its spec.

### Strip a stuck finalizer (last resort)

If the operator cannot finish cleanup and you have confirmed there's no other way forward:

```bash
kubectl patch <kind> <name> -n <ns> \
  --type=json -p='[{"op":"remove","path":"/metadata/finalizers"}]'
```

!!! note "Reach for this only when nothing else works"
    Manual finalizer stripping bypasses the operator's cleanup guarantees. The resource may be removed from the API server while other controllers still hold references to it. Capture the controller logs and the affected resource before running this command, and file a bug report — the operator should not need this in normal operation.

## Reporting a bug

When opening an issue, attach:

- Operator version (`kubectl get deploy controller-manager -n template-operator-system -o jsonpath='{.spec.template.spec.containers[0].image}'`).
- Kubernetes version (`kubectl version --short`).
- The full `Template` and `TemplateInstance` YAMLs (redact secrets).
- The `status` of both CRs at the time of the failure.
- Controller logs from around the time of the failure.
- Any events for the affected resources (`kubectl get events -n <namespace>`).

File the report at the [template-operator-v2 issues page](https://github.com/stakater-ab/template-operator-v2/issues).
