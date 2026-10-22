# Drift Protection

Examples of configuring `Template.spec.sync` to control drift on rendered resources. For the three modes, the comparison rules, and what each one does internally, see [Sync](../concepts/sync.md).

!!! warning "Webhook certificate"
    `sync.mode: strict` relies on the operator's validating webhook, which needs a TLS certificate. The install provides it through cert-manager by default, or through the OpenShift service-ca operator. See [Installation](../installation/overview.md#prerequisites) and [Without cert-manager](../installation/openshift.md#without-cert-manager).

## Scenario 1: enforce a baseline NetworkPolicy (strict)

Bill wants to publish a `NetworkPolicy` that consumers cannot edit or delete by hand. Strict mode rejects unauthorized edits at the API server.

```yaml
apiVersion: templates.v2.stakater.com/v2alpha1
kind: Template
metadata:
  name: tenant-network-policy
  namespace: provider
spec:
  gotemplate: |
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: deny-cross-tenant
    spec:
      podSelector: {}
      policyTypes: [Ingress]
      ingress:
        - from:
            - namespaceSelector:
                matchLabels:
                  kind: tenant
  targetNamespaces:
    selector:
      matchLabels:
        kind: tenant
  sync:
    mode: strict
```

An attempt by a consumer to `kubectl edit` the rendered `NetworkPolicy` is rejected by the admission webhook with a message that points back at the owning `TemplateInstance`. The operator's own reconciles pass through unhindered.

## Scenario 2: keep a Deployment in sync but let HPA scale it (revert + ignoreFields)

Bill publishes a `Deployment` and wants the rendered shape preserved on every reconcile, but Anna runs a `HorizontalPodAutoscaler` against it. HPA scales through the `/scale` subresource, which the webhook does not intercept, but in strict or revert mode the operator reverts the new replica count on the next reconcile when the template renders `spec.replicas`. Revert mode plus `ignoreFields` is the right tool.

```yaml
spec:
  gotemplate: |
    apiVersion: apps/v1
    kind: Deployment
    ...
  sync:
    mode: revert
    ignoreFields:
      - spec.replicas
      - metadata.annotations
```

The controller reverts drift in the fields the template renders, except `spec.replicas` and `metadata.annotations`. It does not revert edits to fields the template does not render. Leave `spec.replicas` out of the rendered `Deployment`: `ignoreFields` only skips drift detection, and any re-apply writes the rendered value back.

## Scenario 3: bootstrap a resource that another controller will own (off)

Bill publishes a `Certificate` for cert-manager to rotate. After cert-manager picks it up, it rewrites the associated `Secret`'s `data` field on rotation. The default `sync.mode: off` is what Bill wants:

```yaml
spec:
  gotemplate: |
    apiVersion: cert-manager.io/v1
    kind: Certificate
    ...
  # sync omitted -> mode defaults to off
```

Resources are applied once and then left alone: after the first clean apply the instance freezes, and neither `Template` nor `TemplateInstance` changes re-apply anything (see [Sync](../concepts/sync.md)).

## Verifying that sync is active

When `sync.mode` is `revert` or `strict`, the `TemplateInstance` reports a `Synced` condition:

```yaml
status:
  conditions:
    - type: Synced
      status: "True"
      reason: SyncActive
```

The `Ready` condition continues to reflect overall reconciliation success.

## Disabling sync without unbinding resources

Changing `Template.spec.sync.mode` back to `off` (or removing `spec.sync` entirely) releases the drift watches on the next reconcile. The rendered resources stay in place; they are no longer enforced.

## See also

- [Sync](../concepts/sync.md) for the model, the three modes, and how the webhook works in strict mode.
- [API reference: `SyncConfig`](../reference/api.md#syncconfig).
