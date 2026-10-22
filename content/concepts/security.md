# Security model

Template Operator v2 runs as a single in-cluster controller that renders and applies resources on behalf of consumers. Three things shape its security posture: the trust boundaries the operator relies on, the permissions that bypass those boundaries, and a handful of lifecycle states an administrator should recognise.

## Trust boundaries

| Boundary | What it protects | Enforced by |
|----------|------------------|-------------|
| The provider namespace | Who can publish a `Template` (and therefore expose anything readable by the operator's service account in that namespace). | Standard Kubernetes RBAC on the provider namespace. |
| `targetNamespaces` on each `Template` | Which consumer namespaces are allowed to instantiate the `Template`. | The operator's `TargetNamespaceAllowed` admission check during reconcile. |
| The operator's service account | What the operator itself can read, list, watch, and apply across the cluster. | The `ClusterRole` and `RoleBinding`s installed by the chart. |
| The drift webhook | Unauthorized UPDATE and DELETE on resources rendered by `strict` `Template`s. | A cluster-wide `ValidatingWebhookConfiguration` that the chart installs. |

The high-level model: **anyone who can write a `Template` in a provider namespace can make the operator write anything its service account can write, and anyone who can create a `TemplateInstance` can make the operator read anything its service account can read** (a `valueFrom` source may name any namespace). Treat both rights as privileged and manage them with RBAC and `targetNamespaces`.

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

## Where rendered resources land

`targetNamespaces` controls which namespaces may **instantiate** a `Template` — not where its rendered resources go. A rendered manifest with an explicit `metadata.namespace` is applied to that namespace; one that omits it defaults to the consumer's (see [Default namespace](./gotemplate.md#default-namespace)). The operator applies every rendered resource with **its own service account**, so:

**The RBAC of the service account the operator applies as is the boundary.** Grant it only the namespaces and resource kinds your Templates actually need — that is how you decide where resources may land, and who (by being allowed to author Templates in a provider namespace) can cause those writes. On default chart RBAC the operator can only manage `Template`s/`TemplateInstance`s and read `Namespace`s, so it is inert until you widen it; widen it deliberately and narrowly. This is intended behaviour, not a gap: scope the grant, not the template.

!!! note "Per-instance service accounts"
    `TemplateInstance.spec.serviceAccountRef` names a `ServiceAccount` in the instance's namespace. The operator **impersonates** it to resolve `valueFrom` parameters and to watch their sources, so that account's RBAC limits what the instance can read. This needs an `impersonate` grant on `serviceaccounts` for the operator, which the chart does not ship. Applies still use the operator's own service account, so scope it as above.

### Optional: an extra guardrail with admission policy

Scoping the operator's RBAC is the primary control. As defence in depth — especially where many Templates share one broadly-permissioned operator — a `ValidatingAdmissionPolicy` can additionally require that a rendered object's namespace matches its owning `TemplateInstance` (or an allow-listed namespace). The operator stamps `templates.v2.stakater.com/instance-namespace` on every rendered object and overwrites any value a template sets, so the policy can trust it:

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: template-operator-v2-write-scope
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
      - apiGroups: ["*"]
        apiVersions: ["*"]
        resources: ["*"]
        operations: ["CREATE", "UPDATE", "DELETE"]
  variables:
    - name: obj
      expression: 'request.operation == "DELETE" ? oldObject : object'
    - name: owner
      expression: 'variables.obj.metadata.?labels[?"templates.v2.stakater.com/instance-namespace"].orValue("")'
  matchConditions:
    - name: is-operator
      expression: 'request.userInfo.username == "system:serviceaccount:<operator-namespace>:<operator-serviceaccount>"'
    - name: is-rendered-object
      expression: '(object != null && "templates.v2.stakater.com/instance-namespace" in object.metadata.?labels.orValue({})) || (oldObject != null && "templates.v2.stakater.com/instance-namespace" in oldObject.metadata.?labels.orValue({}))'
  validations:
    - expression: 'variables.owner in ["<trusted-namespaces>"] || (has(variables.obj.metadata.namespace) && variables.obj.metadata.namespace == variables.owner)'
      messageExpression: '"template-operator-v2: a TemplateInstance in namespace " + variables.owner + " may only write objects in its own namespace"'
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata: { name: template-operator-v2-write-scope }
spec:
  policyName: template-operator-v2-write-scope
  validationActions: [Deny]
```

## Secrets and credentials

- The Helm chart-pull `Secret` referenced by `Template.spec.helm.chart.repository.auth.secretRef` lives in the **provider namespace**, never in the consumer namespace. Consumers never need access to registry credentials.
- Parameters resolved through `valueFrom.secretKeyRef` are read at render time and never written back to the cluster, but the resolved value is passed to the template engine. The `valueFrom` reference is set on the `TemplateInstance`, and its namespace is not restricted: if the `Template` writes the parameter into a resource the instance author can read, that author can read any `Secret` the operator can read. Limit who may instantiate such `Template`s with `targetNamespaces`, or set `spec.serviceAccountRef` on the `TemplateInstance` so that `valueFrom` reads use that account's RBAC.
- Parameters marked `exposeInStatus: true` write their resolved value to `status.resolvedParameters[].value`. Never set `exposeInStatus` on a parameter resolved from a `Secret`.

## See also

- [Lifecycle](./lifecycle.md) for finalizers, ownership labels, and the adoption mechanism.
- [Sync](./sync.md) for drift protection, the webhook, and its edge-case behavior.
- [Parameters](./parameters.md#exposeinstatus-semantics) for `exposeInStatus` semantics.
