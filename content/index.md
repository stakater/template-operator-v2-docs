---
head:
  - - meta
    - name: keywords
      content: template operator, kubernetes, multi-tenancy, templates, helm, gotemplate
---

# Welcome to the Docs

Managing Kubernetes clusters at scale is complex. Platform teams have to keep dozens or hundreds of tenant namespaces consistent, secure, and up to date, while still letting application teams move fast and customize what they need. Doing this by hand quickly turns into copy-pasted YAML, drift between environments, and no clear answer to "who owns this resource and is it still needed?"

**Template Operator v2** is designed to address these challenges by giving platform teams a clean way to publish reusable templates, and giving application teams a simple way to consume them. Templates are authored once, parameterized for each consumer, and rendered into the right namespaces by the operator. With Template Operator v2, you can:

- **Define reusable templates once** and let many teams instantiate them, without copying YAML between namespaces.
- **Parameterize templates** so the same blueprint adapts to each tenant, environment, or use case.
- **Govern who can use a template** by letting the platform team decide which namespaces are allowed to consume it.
- **Bring your own format**: author templates as inline Go templates with [Sprig functions](https://masterminds.github.io/sprig/), or point at an existing Helm chart from a public or private registry.
- **Trust the lifecycle**: when a consumer's needs change, the operator updates and cleans up the resources it created, so nothing is left orphaned.
- **Adopt GitOps naturally**, since both the template and the request to use it are plain Kubernetes resources you can keep in Git.

Template Operator v2 simplifies cluster administration, enhances security, and makes consistent multi-tenancy practical for organizations of any size.

## Two custom resources

| CR | Scope | Purpose |
|----|-------|---------|
| `Template` | Namespaced (provider) | Defines the template body, parameters, and which namespaces may instantiate it |
| `TemplateInstance` | Namespaced (consumer) | References a `Template`, supplies parameter overrides, and owns the rendered resources |

API group / version: **`templates.v2.stakater.com/v2alpha1`**

## Installation

See the [installation guide](./installation/overview.md) to deploy Template Operator v2.

## Where to start

- New to the operator? Read [Concepts](./concepts/overview.md), then walk through [Deploying a template](./how-to-guides/deploying-templates.md).
- Looking for the `Template` field reference? See [Template](./reference/api.md#template).
- Looking for the `TemplateInstance` field reference? See [TemplateInstance](./reference/api.md#templateinstance).
