# Security model

Template Operator v2 runs as a single in-cluster controller that renders and applies resources on behalf of consumers. Three things shape its security posture: the trust boundaries the operator relies on, the permissions that bypass those boundaries, and a handful of lifecycle states an administrator should recognise.

## Trust boundaries

| Boundary | What it protects | Enforced by |
|----------|------------------|-------------|
| The provider namespace | Who can publish a `Template` (and therefore expose anything readable by the operator's service account in that namespace). | Standard Kubernetes RBAC on the provider namespace. |
| `targetNamespaces` on each `Template` | Which consumer namespaces are allowed to instantiate the `Template`. | The operator's `TargetNamespaceAllowed` admission check during reconcile. |
| The operator's service account | What the operator itself can read, list, watch, and apply across the cluster. | The `ClusterRole` and `RoleBinding`s installed by the chart. |
| The drift webhook (strict mode only) | Unauthorized UPDATE and DELETE on managed resources. | A `ValidatingWebhookConfiguration` registered when any `Template` uses `sync.mode: strict`. |

The high-level model: **anyone who can write a `Template` in a provider namespace can render anything the operator's service account can read in that namespace.** Treat write access to a provider namespace as privileged and manage it with RBAC accordingly.

## Permissions that bypass enforcement

### `impersonate` on the operator's service account

The drift webhook lets the operator's own service account through unconditionally, otherwise the operator's reverts would block themselves. Any subject with `impersonate` RBAC on the operator's `ServiceAccount` (or on its user identity) can therefore reach the API server as the operator and bypass the webhook entirely.

**Implication**: treat `impersonate` on the operator's `ServiceAccount` as equivalent to bypassing all sync enforcement. The `impersonate` verb is typically only granted to cluster administrators, and that's the boundary that should be maintained.

**Mitigation**: audit `ClusterRole`s and `RoleBinding`s granting `impersonate` on `users` or `serviceaccounts` resources. The operator's service account should not appear in any allow-list for non-administrative subjects.

### Manual removal of finalizers

The operator relies on three finalizers to enforce its lifecycle guarantees (see [Lifecycle](./lifecycle.md#finalizers)). A cluster administrator who manually strips one of these finalizers can:

- Delete a `Template` while `TemplateInstance`s still reference it. Those instances then enter `TemplateResolved=False, Reason=TemplateNotFound` until they are deleted or pointed elsewhere.
- Delete a `TemplateInstance` without triggering rendered-resource cleanup. The rendered resources stay in the cluster, no longer managed.
- Delete a rendered resource directly. The orphan is still tracked in `status.renderedResources` until the next reconcile reconciles its absence.

The drift webhook handles these unreachable-by-design states by **allowing** the affected request rather than locking it: see [Sync webhook edge cases](./sync.md#webhook-edge-cases-strict-mode). The reasoning is that the resource is already in an inconsistent state with no normal recovery path; denying would lock it permanently.

Manually removing the operator's finalizers is unsupported and should be reserved for incident recovery.

## Resource adoption is identity-based, not provenance-based

Two paths exist to put an existing in-cluster resource under operator management:

- **Annotation-based opt-in**: the user pre-stamps `templates.v2.stakater.com/instance-ref` and waits for the matching `TemplateInstance` to be created. This is the supported migration pattern.
- **Implicit name-collision**: any rendered resource whose `apiVersion`/`kind`/`name`/`namespace` matches an existing in-cluster resource is silently adopted at apply time and **cascade-deleted** when the owning `TemplateInstance` is deleted.

Both paths are documented in [Resource adoption](./lifecycle.md#resource-adoption). The implication for the security model: **a `Template`'s rendered resource names are unrestricted within the consumer's namespace**, and a misnamed template can silently take over and later delete an unrelated resource.

**Mitigation**: include the `TemplateInstance` name in every rendered resource name (`{{ .instance.name }}-config` rather than just `config`), and review new `Template`s before allowing them into a provider namespace.

## Secrets and credentials

- The Helm chart-pull `Secret` referenced by `Template.spec.helm.chart.repository.auth.secretRef` lives in the **provider namespace**, never in the consumer namespace. Consumers never need access to registry credentials.
- Parameters resolved through `valueFrom.secretKeyRef` are read at render time and never written back to the cluster, but the resolved value is passed to the template engine. A template author with access to the provider namespace can render the value into any field of any resource the operator is allowed to create. Treat the right to author a `Template` as equivalent to the right to read every `Secret` the operator can list.
- Parameters marked `exposeInStatus: true` write their resolved value to `status.resolvedParameters[].value`. Never set `exposeInStatus` on a parameter resolved from a `Secret`.

## See also

- [Lifecycle](./lifecycle.md) for finalizers, ownership labels, and the adoption mechanism.
- [Sync](./sync.md) for drift protection, the webhook, and its edge-case behavior.
- [Parameters](./parameters.md#exposeinstatus-semantics) for `exposeInStatus` semantics.
