# Distributing a ConfigMap

A `TemplateInstance` can **read one resource and copy it into many** — and because the source is watched, every copy updates when the source changes. The worked example is a CA bundle distributed to every workload namespace, but the mechanism suits any cluster-wide value.

## Scenario

Bill maintains a CA bundle in a `ConfigMap` `ca-bundle` in the `provider` namespace, and wants a read-only copy named `trusted-ca` in every namespace labelled `team`. Rotating the bundle should update every copy.

## The Template

Two parameters: the source (GET mode — a named `objectFieldRef`) and the target namespaces (LIST mode). With `sync.mode: revert` or `strict`, both are watched, so a change to either re-renders. Under the default `sync.mode: off`, the instance is frozen after its first clean apply.

```yaml
apiVersion: templates.v2.stakater.com/v2alpha1
kind: Template
metadata:
  name: distribute-ca
  namespace: provider
spec:
  parameters:
    - name: caBundle
      required: true
    - name: namespaces
      required: true
  gotemplate: |
    {{- range $ns := .parameters.namespaces }}
    {{- if and (hasKey (default dict (index $ns.metadata "labels")) "team") (not (hasKey $ns.metadata "deletionTimestamp")) }}
    ---
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: trusted-ca
      namespace: {{ $ns.metadata.name }}
    data:
      ca.crt: {{ $.parameters.caBundle | quote }}
    {{- end }}
    {{- end }}
  sync:
    mode: revert     # required: source and namespace changes re-render; a hand-edit of a copy converges back
```

```yaml
apiVersion: templates.v2.stakater.com/v2alpha1
kind: TemplateInstance
metadata:
  name: distribute-ca
  namespace: provider
spec:
  templateRef:
    name: distribute-ca
    namespace: provider
  parameters:
    - name: caBundle
      valueFrom:
        objectFieldRef:
          apiVersion: v1
          kind: ConfigMap
          name: ca-bundle            # named -> GET mode
          namespace: provider
          jsonPath: .data.ca\.crt
    - name: namespaces
      valueFrom:
        objectFieldRef:
          apiVersion: v1
          kind: Namespace
          jsonPath: .items
```

Inside `range`, `.` is the current namespace, so the template reads the bundle through `$.parameters`. The `deletionTimestamp` check skips a namespace that is being deleted, so that namespace can finish its deletion.

Update `ca-bundle` and every `trusted-ca` copy is re-rendered on the next reconcile.

!!! warning "Don't copy Secret material into ConfigMaps"
    This copies a public CA bundle. Never read a `Secret` and render its contents into a `ConfigMap` (or into `status` — see [outputs](../concepts/outputs.md)); that exposes it. For private key material, deliver it where it is needed with a dedicated mechanism rather than fanning it out. A `Secret` is also refused as an output source.

## See also

- [Rendering to many namespaces](./rendering-to-many-namespaces.md) for the fan-out half of this pattern.
- [Parameters: `objectFieldRef` GET vs LIST](../concepts/parameters.md#objectfieldref-get-vs-list) and [`valueFrom.secretKeyRef`](../concepts/parameters.md) for reading secret values safely at render time.
