# Overview

Template Operator v2 is installed via its Helm chart. The same chart targets vanilla Kubernetes, managed Kubernetes (AKS, EKS, GKE, etc.), and OpenShift.

## Prerequisites

Before installing, make sure you have:

- A Kubernetes cluster (v1.24 or higher), or any supported OpenShift version.
- Cluster-admin permissions. Installation creates a `Namespace`, two `CustomResourceDefinitions`, `ClusterRole` / `ClusterRoleBinding` objects, and a `Deployment`.
- `kubectl` (or `oc` for OpenShift).
- `helm` v3.x.

## Custom resources installed

Installation registers two CRDs in the API group `templates.v2.stakater.com`, version `v2alpha1`:

- `templates.templates.v2.stakater.com` (`Template`)
- `templateinstances.templates.v2.stakater.com` (`TemplateInstance`)

## Default namespace

The operator is intended to run in `template-operator-system`. The Helm chart creates this namespace if it doesn't exist.

## Next steps

Pick the guide that matches your environment:

- [Install on Kubernetes](./kubernetes.md)
- [Install on OpenShift](./openshift.md)
