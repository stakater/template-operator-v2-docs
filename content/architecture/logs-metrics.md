# Logs and Metrics

This page describes the operator's runtime signals: structured logs and the metrics endpoint. For how to read CR status fields (conditions, phase, observed generation, resolved parameters, rendered resources), see [Status](../concepts/status.md).

## Logs

The operator uses controller-runtime's structured logger. Every reconcile loop logs at info level on success and error level on failure, with structured fields for `name`, `namespace`, and resource identity. Notable messages:

- `Added finalizer to Template/TemplateInstance`, first-pass after a new resource is observed.
- `Successfully validated Template`, Template controller finished a happy path.
- `Skipping dry-run render: template has parameters without literal values that will be resolved at runtime`, explains why `DryRunRendered` is `False/DryRunSkipped`.
- `Cannot delete Template - still in use by TemplateInstances`, explains why a `Template` deletion is held.
- `Successfully reconciled TemplateInstance`, instance happy path.
- `Applied resource successfully`, emitted per rendered resource.
- `Deleted rendered resource`, emitted per resource during cleanup.
- `Failed to set up parameter watches`, non-fatal; resolution still works via direct GET/LIST but external changes won't trigger re-reconciliation.

## Metrics

The metrics server is the standard controller-runtime metrics endpoint, exposed on `:8443` (HTTPS) or `:8080` (HTTP). It is disabled by default (`--metrics-bind-address=0`); enable it with `--metrics-bind-address=:8443`. When secure, requests are filtered by `WithAuthenticationAndAuthorization`, so callers need a `ClusterRole` granting access to the metrics endpoint (the chart provides `template-operator-v2-metrics-reader`).

The exposed metrics are the controller-runtime defaults: `controller_runtime_reconcile_total`, `controller_runtime_reconcile_errors_total`, `controller_runtime_reconcile_time_seconds`, plus standard Go runtime metrics. There are no custom metrics defined for the Template controllers themselves at this version.
