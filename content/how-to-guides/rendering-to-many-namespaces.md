# Rendering to Many Namespaces

One `TemplateInstance` can render a resource into **every** namespace that matches a rule, and keep the set correct as namespaces come and go. This is the fan-out pattern: a single provider object, N rendered resources, reconciled on change.

## Scenario

Bill wants a `ConfigMap` called `cluster-info` in every namespace labelled `team`, and a new `team` namespace should get one automatically.

## 1. List the namespaces as a parameter

A parameter resolved from an [`objectFieldRef`](../concepts/parameters.md#objectfieldref-get-vs-list) with **no `name`** runs in LIST mode: the operator lists the GVK, passes the whole list to the template, and, with `sync.mode: revert` or `strict`, **watches** it, so adding or removing a namespace re-renders the instance. Under the default `sync.mode: off`, the instance is frozen after its first clean apply.

```yaml
apiVersion: templates.v2.stakater.com/v2alpha1
kind: Template
metadata:
  name: cluster-info
  namespace: provider
spec:
  parameters:
    - name: namespaces
      required: true
  gotemplate: |
    {{- range $ns := .parameters.namespaces }}
    {{- $labels := default dict (index $ns.metadata "labels") }}
    {{- if and (hasKey $labels "team") (not (hasKey $ns.metadata "deletionTimestamp")) }}
    ---
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: cluster-info
      namespace: {{ $ns.metadata.name }}
    data:
      cluster: production
      team: {{ index $labels "team" | quote }}
    {{- end }}
    {{- end }}
  sync:
    mode: revert
```

The gotemplate filters in-template with `hasKey`/`index` rather than a server-side selector, so the one namespace watch covers every rule you might apply. Reading optional keys defensively matters here — see [missing keys are an error](../concepts/gotemplate.md#missing-keys-are-an-error).

The `deletionTimestamp` check skips a namespace that is being deleted. Without it, the rendered `ConfigMap` keeps the operator's finalizer, and the namespace stays in `Terminating`.

## 2. Bind it, listing all namespaces

```yaml
apiVersion: templates.v2.stakater.com/v2alpha1
kind: TemplateInstance
metadata:
  name: cluster-info
  namespace: provider
spec:
  templateRef:
    name: cluster-info
    namespace: provider
  parameters:
    - name: namespaces
      valueFrom:
        objectFieldRef:
          apiVersion: v1
          kind: Namespace
          jsonPath: .items        # no name -> LIST mode, returns every Namespace
```

## 3. Watch it track the cluster

```bash
kubectl label namespace team-a team=a
kubectl label namespace team-b team=b
kubectl get configmap -A --field-selector metadata.name=cluster-info   # one per labelled namespace

kubectl create namespace team-c && kubectl label namespace team-c team=c
kubectl get configmap cluster-info -n team-c # appears without touching the TemplateInstance
```

## RBAC and scope

The rendered `ConfigMap`s carry an explicit `metadata.namespace`, so the operator writes them into those namespaces — the operator's service account needs `configmaps` write there, and the write is not limited by `targetNamespaces`. Review [Security → where rendered resources land](../concepts/security.md#where-rendered-resources-land) before fanning out across namespaces you do not control.

## See also

- [Composing TemplateInstances](./composing-templateinstances.md) when each item needs its own status and failure isolation.
- [Parameters: `objectFieldRef` GET vs LIST](../concepts/parameters.md#objectfieldref-get-vs-list).
