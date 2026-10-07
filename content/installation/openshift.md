# On OpenShift

The Template Operator v2 Helm chart targets OpenShift the same way it targets any other Kubernetes distribution. There is no OpenShift-specific install path.

## Requirements

- An OpenShift cluster.
- Cluster-admin access via `oc` or an equivalent GitOps tool.
- [Helm](https://helm.sh/docs/intro/install/) v3.x.

## Installing via Helm

```bash
helm install template-operator-v2 \
  oci://ghcr.io/stakater/charts/template-operator-v2 \
  --namespace template-operator-system \
  --create-namespace
```

Wait for the controller to come up:

```bash
oc get pods -n template-operator-system --watch
```

The deployment is named `controller-manager` and should reach `Ready 1/1`.

## Verifying the install

```bash
oc get crd | grep templates.v2.stakater.com
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

The CRDs remain installed by default. Remove them manually if you do not plan to reinstall:

```bash
oc delete crd templates.templates.v2.stakater.com
oc delete crd templateinstances.templates.v2.stakater.com
```

!!! warning
    Deleting CRDs cascades to every `Template` and `TemplateInstance` in the cluster, which in turn deletes every resource the operator has rendered. Make sure that's what you want before running these commands.
