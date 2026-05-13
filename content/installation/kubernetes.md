# On Kubernetes

This guide covers installing and uninstalling Template Operator v2 on a vanilla Kubernetes cluster using the Helm chart.

## Requirements

- A Kubernetes cluster, v1.24 or higher.
- [Helm](https://helm.sh/docs/intro/install/) v3.x.
- [kubectl](https://kubernetes.io/docs/tasks/tools/).

## Installing via Helm

The Helm chart is published to GitHub Container Registry as an OCI artifact:

```bash
helm install template-operator-v2 \
  oci://ghcr.io/stakater/charts/template-operator-v2 \
  --namespace template-operator-system \
  --create-namespace
```

!!! note
    `template-operator-system` is the recommended namespace; the chart's manifests reference it by default.

Wait for the controller to come up:

```bash
kubectl get pods -n template-operator-system --watch
```

The deployment is named `controller-manager` and should reach `Ready 1/1`.

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

```bash
helm uninstall template-operator-v2 --namespace template-operator-system
```

The CRDs remain installed by default (Helm does not delete CRDs created by a chart). Remove them manually if you do not plan to reinstall:

```bash
kubectl delete crd templates.templates.v2.stakater.com
kubectl delete crd templateinstances.templates.v2.stakater.com
```

!!! warning
    Deleting CRDs cascades to every `Template` and `TemplateInstance` in the cluster, which in turn deletes every resource the operator has rendered. Make sure that's what you want before running these commands.
