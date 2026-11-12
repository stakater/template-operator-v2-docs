---
head:
  - - meta
    - name: keywords
      content: template operator, kubernetes, multi-tenancy, templates, helm, gotemplate
---

# Welcome to the Docs

**Template Operator v2** lets platform teams publish reusable, parameterized templates and lets application teams instantiate them in their namespaces. Read the [Introduction](./about/introduction.md) for what it does and why.

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
