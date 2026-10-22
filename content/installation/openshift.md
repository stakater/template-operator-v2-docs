# On OpenShift

The Template Operator v2 Helm chart targets OpenShift the same way it targets any other Kubernetes distribution. The only difference is where the webhook certificate comes from: cert-manager, or the OpenShift service-ca operator.

## Requirements

- An OpenShift cluster.
- Cluster-admin access via `oc` or an equivalent GitOps tool.
- [Helm](https://helm.sh/docs/intro/install/) v3.x.
- cert-manager (for example the cert-manager Operator for Red Hat OpenShift), or the values in [Without cert-manager](#without-cert-manager).

## Installing via Helm

```bash
helm install template-operator-v2 \
  oci://ghcr.io/stakater/public/charts/template-operator-v2 \
  --namespace template-operator-system \
  --create-namespace
```

Wait for the controller to come up:

```bash
oc get pods -n template-operator-system --watch
```

The deployment is named `template-operator-v2-controller-manager` and should reach `Ready 1/1`.

Then grant the operator the kinds your `Template`s use, as described in [Granting permissions to rendered kinds](./kubernetes.md#granting-permissions-to-rendered-kinds).

## Without cert-manager

The operator's admission webhook needs a TLS certificate. Without cert-manager, let the OpenShift service-ca operator issue it:

```yaml
# values.yaml
certManager:
  enabled: false
webhookConfig:
  annotations:
    service.beta.openshift.io/inject-cabundle: "true"
webhookService:
  annotations:
    service.beta.openshift.io/serving-cert-secret-name: template-operator-v2-webhook-server-cert
```

Pass the file with `-f values.yaml` to the `helm install` command above. The Secret name must match the chart's `webhook.certSecretName`.

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

Delete the `TemplateInstance`s and `Template`s first, while the operator still runs:

```bash
oc delete templateinstances.templates.v2.stakater.com --all -A
oc delete templates.templates.v2.stakater.com --all -A
```

Then remove the chart. The CRDs remain installed; remove them if you do not plan to reinstall:

```bash
helm uninstall template-operator-v2 --namespace template-operator-system
oc delete crd templates.templates.v2.stakater.com
oc delete crd templateinstances.templates.v2.stakater.com
```

!!! warning
    If you uninstall the chart before you delete the `Template`s and `TemplateInstance`s, the CRD deletes hang: the remaining objects keep their finalizers, and no controller is left to remove them. Install the chart again to let the operator finish the cleanup.
