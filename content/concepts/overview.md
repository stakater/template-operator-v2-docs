# Overview

Template Operator v2 has exactly two custom resources. Once you understand the relationship between them, the rest of the operator is a small extension of that idea.

## The provider/consumer split

A `Template` is the **provider's** artifact. It lives in a provider namespace, contains the template body, declares the parameters it accepts, and decides which other namespaces are allowed to use it. A `Template` produces nothing on its own.

A `TemplateInstance` is the **consumer's** artifact. It lives in a consumer namespace, references a `Template` by name and namespace, and supplies parameter values. Creating a `TemplateInstance` is the action that causes the operator to render the template body and apply the resulting Kubernetes resources.

```
              provider namespace                    consumer namespace
       ┌───────────────────────────────┐    ┌───────────────────────────────┐
       │ Template "foo-template"       │◄───│ TemplateInstance "my-app"     │
       │   spec.gotemplate / spec.helm │    │   spec.templateRef            │
       │   spec.parameters             │    │   spec.parameters (overrides) │
       │   spec.targetNamespaces       │    │                               │
       │   spec.sync                   │    │ status.renderedResources      │
       └───────────────────────────────┘    └───────────────────────────────┘
                                                          │
                                                          ▼
                                                rendered Kubernetes resources
                                                in the consumer namespace
```

## Why two resources

The split keeps three concerns separate:

- **Authorship**: the platform team owns the `Template` and curates the surface (parameters, allowed namespaces, drift policy).
- **Consumption**: application teams own their `TemplateInstance` and supply environment-specific values.
- **RBAC**: write access to a provider namespace is privileged; read-only access to it is enough to consume what's published there.

It also enables one-to-many fan-out: a single `Template` can be instantiated by any number of `TemplateInstance` resources, in any number of permitted namespaces, each with its own parameter values.

## Two rendering engines

A `Template` exposes one of two engines, enforced by an API-level rule (`has(self.gotemplate) != has(self.helm)`):

- [`spec.gotemplate`](./gotemplate.md): inline Go template with Sprig functions.
- [`spec.helm`](./helm.md): a chart pulled from an HTTP/HTTPS or OCI registry.

Both engines see the same data (`.parameters`, `.instance`) and produce the same kind of output: a stream of Kubernetes manifests the operator then applies.

## The top-level fields, at a glance

The remaining concept pages cover one top-level field each.

| Field | Concept page | What it controls |
|-------|--------------|-------------------|
| `Template.spec.gotemplate` | [Gotemplate](./gotemplate.md) | Inline Go template body. |
| `Template.spec.helm` | [Helm](./helm.md) | Helm chart source and rendering configuration. |
| `Template.spec.parameters` | [Parameters](./parameters.md) | Inputs the template accepts, with optional typing and override rules. |
| `Template.spec.targetNamespaces` | [Target namespaces](./target-namespaces.md) | Which consumer namespaces are permitted to instantiate. |
| `Template.spec.sync` | [Sync](./sync.md) | Drift protection: `off`, `revert`, or `strict`. |
| `TemplateInstance.spec.parameters` | [Parameters](./parameters.md#instance-side-overrides) | Consumer-side overrides, including dynamic `valueFrom` resolution. |
| `status.*` | [Status](./status.md) | Phase, conditions, resolved parameters, rendered-resource list, tracked GVKs. |
| Finalizers and cleanup | [Lifecycle](./lifecycle.md) | Dry-run gate, orphan cleanup, deletion semantics. |

## API surface

For the exact field list, validation rules, and defaults, see the auto-generated [API reference](../reference/api.md). These concept pages explain the *why* and *how*; the reference is the *what*.
