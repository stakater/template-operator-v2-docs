# Overview

Template Operator v2 is installed via its Helm chart. The same chart targets vanilla Kubernetes, managed Kubernetes (AKS, EKS, GKE, etc.), and OpenShift.

## Prerequisites

Before installing, make sure you have:

- A Kubernetes cluster (v1.24 or higher), or any supported OpenShift version.
- Cluster-admin permissions. Installation creates a `Namespace`, two `CustomResourceDefinitions`, `ClusterRole` / `ClusterRoleBinding` objects, and a `Deployment`.
- `kubectl` (or `oc` for OpenShift).
- `helm` v3.x.
- [cert-manager](https://cert-manager.io/docs/installation/) on the cluster. The operator always runs its admission webhook, and the chart issues the webhook's TLS certificate through cert-manager. On OpenShift, the service-ca operator can issue it instead; see [Install on OpenShift](./openshift.md#without-cert-manager).

## Custom resources installed

Installation registers two CRDs in the API group `templates.v2.stakater.com`, version `v2alpha1`:

- `templates.templates.v2.stakater.com` (`Template`)
- `templateinstances.templates.v2.stakater.com` (`TemplateInstance`)

## Default namespace

The operator is intended to run in `template-operator-system`. The Helm chart creates this namespace if it doesn't exist.

## Already running Multi-Tenant Operator?

If the cluster runs Stakater's Multi-Tenant Operator (MTO), you do not install this chart directly — MTO can deploy and manage Template Operator v2 for you. Set `components.templateOperatorV2.mode: Managed` in the `IntegrationConfig`, and MTO runs the operator in its own namespace. The guides below are for a standalone install.

## Next steps

Pick the guide that matches your environment:

- [Install on Kubernetes](./kubernetes.md)
- [Install on OpenShift](./openshift.md)
