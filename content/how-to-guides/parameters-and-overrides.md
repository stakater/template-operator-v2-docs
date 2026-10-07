# Parameters and Overrides

Examples of declaring parameters on a `Template` and overriding them from a `TemplateInstance`. For the resolution model, validation rules, namespace scoping, JSONPath syntax, watch semantics, and RBAC, see [Parameters](../concepts/parameters.md).

## Scenario 1: literal defaults overridden by the instance

Bill publishes a `Template` with literal defaults so simple consumers can use it without supplying anything.

```yaml
apiVersion: templates.v2.stakater.com/v2alpha1
kind: Template
metadata:
  name: app-template
  namespace: provider
spec:
  parameters:
    - name: replicas
      value: "2"
    - name: image
      value: ghcr.io/stakater/app:latest
    - name: env
      value: production
  gotemplate: |
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: app
    spec:
      replicas: {{ .parameters.replicas }}
      template:
        spec:
          containers:
            - name: app
              image: {{ .parameters.image }}
              env:
                - name: APP_ENV
                  value: {{ .parameters.env }}
```

Anna's `TemplateInstance` keeps the defaults except for the image:

```yaml
apiVersion: templates.v2.stakater.com/v2alpha1
kind: TemplateInstance
metadata:
  name: app
  namespace: team-a
spec:
  templateRef:
    name: app-template
    namespace: provider
  parameters:
    - name: image
      value: ghcr.io/stakater/app:v1.4.0
```

`status.resolvedParameters` records that `image` was overridden and the other two used the `Template`'s defaults.

## Scenario 2: read a database password from a Secret

Anna's namespace already has a `db-credentials` Secret. She wants the `TemplateInstance` to read the password at render time so it doesn't appear in YAML or git history.

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-credentials
  namespace: team-a
type: Opaque
stringData:
  password: s3cret
---
apiVersion: templates.v2.stakater.com/v2alpha1
kind: TemplateInstance
metadata:
  name: app
  namespace: team-a
spec:
  templateRef:
    name: app-template
    namespace: provider
  parameters:
    - name: dbPassword
      valueFrom:
        secretKeyRef:
          name: db-credentials
          key: password
```

The `Secret` value is base64-decoded automatically. The operator subscribes to the `Secret` and re-reconciles the `TemplateInstance` whenever the password is rotated.

## Scenario 3: read the ingress IP via `objectFieldRef` (GET)

Anna wants the rendered `ConfigMap` to include the load-balancer IP of an existing `Ingress`. The IP is in the `Ingress.status.loadBalancer.ingress[0].ip` field.

```yaml
apiVersion: templates.v2.stakater.com/v2alpha1
kind: TemplateInstance
metadata:
  name: app
  namespace: team-a
spec:
  templateRef:
    name: app-template
    namespace: provider
  parameters:
    - name: ingressIP
      valueFrom:
        objectFieldRef:
          apiVersion: networking.k8s.io/v1
          kind: Ingress
          name: my-ingress
          namespace: team-a
          jsonPath: .status.loadBalancer.ingress[0].ip
```

`name` is set, so this is GET mode and the result is a single string. The template uses `{{ .parameters.ingressIP }}` as a scalar.

## Scenario 4: list discovered services via `objectFieldRef` (LIST)

Anna wants the rendered `ConfigMap` to list every `ConfigMap` name in her namespace, no matter how many there are.

`Template`:

```yaml
spec:
  parameters:
    - name: serviceNames
  gotemplate: |
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: discovered-services
    data:
      services: |
        {{- range .parameters.serviceNames }}
        - {{ . }}
        {{- end }}
```

`TemplateInstance`:

```yaml
spec:
  parameters:
    - name: serviceNames
      valueFrom:
        objectFieldRef:
          apiVersion: v1
          kind: ConfigMap
          namespace: team-a
          jsonPath: .items[*].metadata.name
```

Because `name` is omitted, this is LIST mode and `serviceNames` is always a list, so the template's `{{ range }}` is safe even when only one match is found.

## Scenario 5: fall back when the optional source is missing

Anna's chart can run with a default password but should pick up a real one from a `Secret` if it exists. She combines `valueFrom` with `defaultValue`:

```yaml
spec:
  parameters:
    - name: dbPassword
      valueFrom:
        secretKeyRef:
          name: db-credentials
          key: password
      defaultValue: changeme
```

If `db-credentials` does not exist, or the `password` key is missing, the resolution **fails** and the operator uses `changeme`. If the Secret exists with an empty `password` value, the empty string is used as-is, since the resolution succeeded.

## See also

- [Parameters](../concepts/parameters.md) for the resolution model, type validation, watch semantics, and RBAC.
- [Parameter validation](./parameter-validation.md) for `type` / `required` / `disableOverride` / `exposeInStatus`.
- [API reference: `TemplateParameter`](../reference/api.md#templateparameter).
