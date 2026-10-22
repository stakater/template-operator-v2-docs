# Versioning and Compatibility

Template Operator v2 is pre-1.0 and its API is at an alpha version. This page is what you need to know before you depend on it, and before you upgrade.

## API version

The custom resources are served at **`templates.v2.stakater.com/v2alpha1`**. An alpha version signals that the schema and behaviour may still change between releases. Build against it, but pin the operator version you tested with (below) rather than tracking `latest`.

## Kubernetes version

In chart 0.0.8 the CRDs carry a CEL validation rule on `objectFieldRef` that older Kubernetes cannot compile: they install on **Kubernetes 1.32+** (OpenShift 4.19+) and fail to install on 1.31. Releases after 0.0.8 install on **Kubernetes 1.29+**. Match this in CI — the kind node image you test on must meet the minimum for the chart version you pin.

## Pin the operator version

Install and test against an explicit chart version, not a floating tag, and record it:

```bash
helm install template-operator-v2 \
  oci://ghcr.io/stakater/public/charts/template-operator-v2 \
  --version <x.y.z> \
  --namespace template-operator-system --create-namespace
```

The chart pins a matching controller image, so the chart version is the one number you need to track. If you vendor the CRDs for [admission tests](../how-to-guides/testing-templates.md#admission-tests-will-the-api-server-accept-the-cr), vendor them from the same version and refresh them when you bump it.

## Behaviour has changed across releases

Treat rendering and lifecycle behaviour as version-specific. Two examples that have changed and will affect a template or an integration:

- **`missingkey=error` rendering.** Recent versions render gotemplates with Go's `missingkey=error` option, so reading a missing map key fails the render; earlier versions emitted `<no value>`. A template that reads optional keys as struct fields can pass on an older operator and fail on a newer one. Read keys defensively — see [missing keys are an error](../concepts/gotemplate.md#missing-keys-are-an-error).
- **Retain-on-delete.** Whether a rendered resource annotated `templates.v2.stakater.com/deletion-policy: Orphan` is *released* (kept) or *deleted* when its owning `TemplateInstance` goes away depends on the operator version — older operators delete it regardless. If your integration relies on keeping objects after teardown, require the version that honours the annotation.

The point is not the specific versions but the discipline: **pin, read the [changelog](../changelog.md) before upgrading, and re-run your [tests](../how-to-guides/testing-templates.md) against the new version.**

## See also

- [Changelog](../changelog.md) for the API-version history (per-release notes are not published yet).
- [Testing Templates](../how-to-guides/testing-templates.md) for catching behavioural drift when you upgrade.
- [API reference](./api.md) for the current schema.
