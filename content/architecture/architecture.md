# Architecture

Template Operator v2 ships as a single controller-manager Deployment. The same process hosts two independent reconcilers, one for `Template` and one for `TemplateInstance`, alongside the Helm renderer pool and the dynamic-informer registry. The reconcilers are separate goroutines and share no state directly; they coordinate through the API server and the informer cache.

## Components

| Name | Type | Description |
|------|------|-------------|
| `controller-manager` | Deployment | One pod (default replicas: 1) that runs both reconcilers, the Helm renderer pool, the dynamic-informer registry, and the metrics server. Leader election is enabled via `--leader-elect`. |
| `Template` reconciler | Goroutine | Validates `Template` CRs: parses the Go template, dry-run renders it (when all parameters have literal defaults), and for Helm templates pulls the chart from the configured repository. |
| `TemplateInstance` reconciler | Goroutine | Resolves parameters, renders the template, applies rendered resources via server-side apply, and tracks them in `status.renderedResources`. |
| Helm renderer pool | In-process | Two `ChartRenderer` implementations (one for Helm v3 SDK, one for Helm v4 SDK) selected by `Template.spec.helm.version`. |
| Dynamic informer registry | In-process | Sets up watches for every `Secret`/`ConfigMap`/arbitrary resource referenced by a `TemplateInstance` parameter's `valueFrom`. Re-enqueues the `TemplateInstance` when the source changes. Default resync period: 30 seconds. |

## Watches

The `TemplateInstance` controller watches three sources:

- `TemplateInstance` itself (predicate: `GenerationChangedPredicate ∨ AnnotationChangedPredicate`).
- `Template` (re-enqueues every `TemplateInstance` that references the changed `Template`).
- A generic event channel fed by the dynamic informer registry for `valueFrom` source changes.

The `Template` controller watches only itself.

## Metrics & probes

| Endpoint | Default | Purpose |
|----------|---------|---------|
| `/healthz` | `:8081` | Liveness, controller-runtime `healthz.Ping`. |
| `/readyz` | `:8081` | Readiness, controller-runtime `healthz.Ping`. |
| `/metrics` | `:8443` HTTPS (default-disabled binding `0`) | Controller-runtime metrics. Authn/authz via `WithAuthenticationAndAuthorization` filter when `--metrics-secure=true`. |

HTTP/2 is disabled by default for both metrics and webhook servers (see [GHSA-qppj-fm5r-hxr3](https://github.com/advisories/GHSA-qppj-fm5r-hxr3) and [GHSA-4374-p667-p6c8](https://github.com/advisories/GHSA-4374-p667-p6c8)).
