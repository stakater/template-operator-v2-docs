# Deploying a Template

This guide walks through the basic flow: a platform team creates a `Template` in a provider namespace, and a consumer team creates a `TemplateInstance` in their own namespace to render it.

## Scenario

Bill is a platform admin who wants to publish a reusable `Pod` blueprint. Anna leads team A and wants to use that blueprint, with her own values, in `team-a`.

## 1. Bill creates the namespaces and the Template

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: foo
---
apiVersion: v1
kind: Namespace
metadata:
  name: team-a
---
apiVersion: templates.v2.stakater.com/v2alpha1
kind: Template
metadata:
  name: foo-template
  namespace: foo
spec:
  gotemplate: |
    apiVersion: v1
    kind: Pod
    metadata:
      name: {{ .parameters.name }}
      namespace: {{ .instance.namespace }}
      labels:
        app: {{ .parameters.name }}
        managed-by: template-operator
    spec:
      restartPolicy: {{ .parameters.restartPolicy }}
      containers:
        - name: app
          image: {{ .parameters.image }}
          env:
            - name: ENDPOINT
              value: {{ .parameters.endpoint }}
          ports:
            - containerPort: 80
  parameters:
    - name: name
      value: example
    - name: image
      value: nginx:latest
    - name: endpoint
      value: http://default-endpoint
    - name: restartPolicy
      value: Always
  targetNamespaces:
    explicit:
      allow:
        literal:
          - team-a
```

Apply it:

```bash
kubectl apply -f template.yaml
```

Confirm the `Template` validated:

```bash
kubectl -n foo get template foo-template -o jsonpath='{.status.phase}'
```

Expected output:

```console
Valid
```

## 2. Anna creates a TemplateInstance

```yaml
apiVersion: templates.v2.stakater.com/v2alpha1
kind: TemplateInstance
metadata:
  name: my-app
  namespace: team-a
spec:
  templateRef:
    name: foo-template
    namespace: foo
  parameters:
    - name: name
      value: my-custom-pod
    - name: image
      value: nginx:1.27
    - name: endpoint
      value: http://api.team-a.svc
    - name: restartPolicy
      value: OnFailure
```

```bash
kubectl apply -f templateinstance.yaml
```

Confirm the instance is `Ready`:

```bash
kubectl -n team-a get templateinstance my-app
```

Expected output:

```console
NAME     PHASE
my-app   Ready
```

The rendered `Pod` is now in `team-a`:

```bash
kubectl -n team-a get pod my-custom-pod
```

## 3. Inspect what was rendered

`status.renderedResources` lists the resources the operator owns for this instance:

```bash
kubectl -n team-a get templateinstance my-app -o yaml
```

```yaml
status:
  phase: Ready
  resolvedTemplateRef:
    name: foo-template
    namespace: foo
    generation: 1
  resolvedParameters:
    - name: name
    - name: image
    - name: endpoint
    - name: restartPolicy
  renderedResources:
    - apiVersion: v1
      kind: Pod
      name: my-custom-pod
      namespace: team-a
  conditions:
    - type: Ready
      status: "True"
      reason: Reconciled
```

## 4. Updating

Editing the `TemplateInstance`'s parameters re-renders. Editing the `Template` re-enqueues every `TemplateInstance` that references it. In both cases, resources that were rendered before but not after are deleted.

## 5. Deleting

```bash
kubectl -n team-a delete templateinstance my-app
```

Every resource in `status.renderedResources` is deleted, the operator's finalizer is stripped, then the `TemplateInstance`'s own finalizer is removed.

To delete the `Template`, first delete every `TemplateInstance` that references it. Otherwise the deletion is held with `Deleting=False, Reason=DeletionBlocked`.
