# On Kubernetes

This guide covers installing and uninstalling Template Operator v2 on a vanilla Kubernetes cluster using the Helm chart.

## Requirements

- A Kubernetes cluster, v1.24 or higher.
- [Helm](https://helm.sh/docs/intro/install/) v3.x.
- [kubectl](https://kubernetes.io/docs/tasks/tools/).
- [cert-manager](https://cert-manager.io/docs/installation/), installed before the chart. The chart issues the operator's webhook certificate through it.

## Installing via Helm

The Helm chart is published to GitHub Container Registry as an OCI artifact:

```bash
helm install template-operator-v2 \
  oci://ghcr.io/stakater/public/charts/template-operator-v2 \
  --namespace template-operator-system \
  --create-namespace
```

!!! note
    `template-operator-system` is the recommended namespace; the chart's manifests reference it by default.

Wait for the controller to come up:

```bash
kubectl get pods -n template-operator-system --watch
```

The deployment is named `template-operator-v2-controller-manager` and should reach `Ready 1/1`.

## Granting permissions to rendered kinds

The chart's `ClusterRole` lets the operator manage only its own CRDs and read `Namespace`s. Before a `TemplateInstance` can render, grant the operator every kind your `Template`s render, and every kind a parameter reads through `valueFrom` (including `Secret`s and `ConfigMap`s). Add the rules through `rbac.additionalRules`:

```yaml
# values.yaml
rbac:
  additionalRules:
    - apiGroups: [""]
      resources: [configmaps, pods]
      verbs: [get, list, watch, create, update, patch, delete]
    - apiGroups: [""]
      resources: [secrets]
      verbs: [get, list, watch]
    - apiGroups: [apps]
      resources: [deployments]
      verbs: [get, list, watch, create, update, patch, delete]
```

```bash
helm upgrade --install template-operator-v2 \
  oci://ghcr.io/stakater/public/charts/template-operator-v2 \
  --namespace template-operator-system \
  -f values.yaml
```

Grant only the kinds your `Template`s need. See [Security: where rendered resources land](../concepts/security.md#where-rendered-resources-land).

## Verifying the install

```bash
kubectl get crds | grep templates.v2.stakater.com
```

Expected output:

```console
templates.templates.v2.stakater.com
templateinstances.templates.v2.stakater.com
```

## Uninstalling

Delete the `TemplateInstance`s and `Template`s first, while the operator still runs. The operator removes each instance's rendered resources and then its own finalizers:

```bash
kubectl delete templateinstances.templates.v2.stakater.com --all -A
kubectl delete templates.templates.v2.stakater.com --all -A
```

Then remove the chart. The CRDs remain installed (Helm does not delete CRDs created by a chart); remove them if you do not plan to reinstall:

```bash
helm uninstall template-operator-v2 --namespace template-operator-system
kubectl delete crd templates.templates.v2.stakater.com
kubectl delete crd templateinstances.templates.v2.stakater.com
```

!!! warning
    If you uninstall the chart before you delete the `Template`s and `TemplateInstance`s, the CRD deletes hang: the remaining objects keep their finalizers, and no controller is left to remove them. Install the chart again to let the operator finish the cleanup.
