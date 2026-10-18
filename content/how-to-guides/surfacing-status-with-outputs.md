# Surfacing Status with Outputs

A rendered resource gets values at runtime that the author never wrote — an allocated address, a generated name, a downstream controller's health. [`outputs`](../concepts/outputs.md) lift those back onto the `TemplateInstance`'s status, so a consumer (or another `Template`) can read them from one object instead of querying the rendered resources.

## Scenario 1: expose an allocated LoadBalancer IP

Anna renders a `Service` of type `LoadBalancer` and wants the address the cloud assigns, without running `kubectl get svc` herself.

```yaml
apiVersion: templates.v2.stakater.com/v2alpha1
kind: Template
metadata:
  name: edge-service
  namespace: provider
spec:
  parameters:
    - name: name
      required: true
  gotemplate: |
    apiVersion: v1
    kind: Service
    metadata:
      name: {{ .parameters.name }}
    spec:
      type: LoadBalancer
      selector:
        app: {{ .parameters.name }}
      ports:
        - port: 80
  outputs:
    - name: endpoint
      from:
        apiVersion: v1
        kind: Service
        name: "{.parameters.name}"      # JSONPath template over the Template context
      fields:
        - name: ip
          jsonPath: "{.status.loadBalancer.ingress[*].ip}"
        - name: clusterIP
          jsonPath: "{.spec.clusterIP}"
```

Once the cloud assigns an address, it appears on the instance:

```bash
kubectl get templateinstance edge-service -n consumer-a \
  -o jsonpath='{.status.outputs.endpoint}' | jq .
# { "ip": "203.0.113.7", "clusterIP": "10.96.12.34" }
```

A field whose JSONPath matches nothing yet (the IP before the cloud assigns it) simply stays unresolved and is reflected on the `OutputsResolved` condition — it does not fail the instance.

## Scenario 2: roll up the health of many rendered resources

When one instance renders several resources of a kind, `fromAll` keys an entry per resource, so the instance's status answers "is every one healthy?":

```yaml
  outputs:
    - name: deployments
      fromAll:
        apiVersion: apps/v1
        kind: Deployment
      keyTemplate: "{.metadata.name}"
      fields:
        - name: available
          jsonPath: "{.status.availableReplicas}"
```

```bash
kubectl get templateinstance <name> -n <ns> -o jsonpath='{.status.outputs.deployments}' | jq .
# { "web": { "available": "3" }, "worker": { "available": "1" } }
```

## Notes

- An array or object result is JSON-encoded into the status string (`{.status.loadBalancer.ingress[*].ip}` → `'["203.0.113.7"]'`); a scalar is stored as-is.
- A `Secret` may not be an output source, so secret material can never be copied into status.

## See also

- [Outputs](../concepts/outputs.md) for the full semantics of `from`, `fromAll`, `forEach` and `keyTemplate`.
- [Status](../concepts/status.md) for where outputs sit and the `OutputsResolved` condition.
