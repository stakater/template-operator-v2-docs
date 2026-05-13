# Benefits of Template Operator v2

Template Operator v2 lets a platform team define reusable template artifacts (Go templates or Helm charts) that consumer teams instantiate into their own namespaces with their own parameters. The operator handles rendering, applying, finalization, and clean-up.

## 1. Author once, instantiate many

Platform teams maintain a single `Template` in their provider namespace. Any number of `TemplateInstance` resources, in any permitted consumer namespace, can render that `Template` with their own parameter overrides.

## 2. Two rendering engines

A `Template` is either a Go template (`spec.gotemplate`), with the full Go `text/template` syntax plus a sandboxed [Sprig](https://masterminds.github.io/sprig/) function set, or a Helm chart (`spec.helm`) pulled from an `HTTP`, `HTTPS`, or OCI repository. Exactly one is required; the API forbids both. The same parameter machinery feeds either engine.

## 3. Parameter resolution at render time

Parameter overrides on a `TemplateInstance` can be:

- Literal strings.
- `valueFrom.secretKeyRef` / `configMapKeyRef`, resolves a key from a `Secret` or `ConfigMap` at render time.
- `valueFrom.objectFieldRef`, resolves a JSONPath against any cluster resource by GVK, in either GET (named resource) or LIST (all resources of a kind, with wildcards) mode.

!!! note
    Resolution is fail-fast: if any single parameter can't be resolved, the instance does not render with partial values.

## 4. Namespace-scoped authorization

A `Template`'s `targetNamespaces` field controls which consumer namespaces are allowed to instantiate it. The default, when `targetNamespaces` is omitted, is that only `TemplateInstance`s in the `Template`'s own namespace are permitted. An explicit allow-list, a namespace label selector, or the wildcard `*` opens it up further.

## 5. Standard Kubernetes status reporting

Every CR follows Kubernetes status conventions: a `phase`, an `observedGeneration`, and a list of `conditions` with `Reason` and `Message`. There is no operator-specific status format to learn, `kubectl describe`, `kubectl wait --for=condition=Ready`, and tools like ArgoCD integrate naturally.

## 6. Rendered-resource lifecycle is tracked

The operator stamps each rendered resource with a finalizer and records its `apiVersion`, `kind`, `name`, and `namespace` in `status.renderedResources`. Deleting the `TemplateInstance` cleanly removes every rendered resource. Updating a `Template` to render a smaller set causes orphans to be deleted on the next reconcile.

## 7. GitOps-friendly

Both CRs are plain Kubernetes resources with declarative spec. Anything you can express in YAML you can manage with Argo CD, Flux, or `kubectl apply -f`.
