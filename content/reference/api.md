# API Reference

## Packages

- [templates.v2.stakater.com/v2alpha1](#templatesv2stakatercomv2alpha1)

## templates.v2.stakater.com/v2alpha1

Package v2alpha1 contains API Schema definitions for the templates v2alpha1 API group.

### Resource Types

- [Template](#template)
- [TemplateInstance](#templateinstance)

#### Template

Template is a reusable blueprint that defines Kubernetes resources which can be
instantiated multiple times across different namespaces using TemplateInstances.
Templates are scoped to a provider namespace and contain go templates or Helm charts
that render into one or more Kubernetes manifests when instantiated.

Namespace Scope (Provider):
The Template may only reference other resources in its own namespace.

Security Implication:
Anyone who can create a Template in a namespace can expose any resource that the
template-operator service account is allowed to read within that namespace.

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `apiVersion` _string_ | `templates.v2.stakater.com/v2alpha1` | | |
| `kind` _string_ | `Template` | | |
| `metadata` _[ObjectMeta](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.30/#objectmeta-v1-meta)_ | Refer to Kubernetes API documentation for fields of `metadata`. |  |  |
| `spec` _[TemplateSpec](#templatespec)_ |  |  |  |
| `status` _[TemplateStatus](#templatestatus)_ |  |  | Optional: \{\} <br /> |

#### TemplateSpec

TemplateSpec defines the desired state of Template

_Appears in:_

- [Template](#template)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `gotemplate` _string_ | Exactly one of `gotemplate` or `helm` must be specified.<br />gotemplate is rendered using Go text/template.<br />It may emit one or more Kubernetes manifests.<br />Sprig functions are also available <https://masterminds.github.io/sprig/><br />If a namespace-scoped resource omits the namespace field,<br />it will be created in the TemplateInstance's namespace (consumer namespace),<br />NOT in the 'default' namespace or the Template's namespace.<br />Available context (non-exhaustive):<br />- .parameters : resolved parameter values<br />- .instance   : metadata of the TemplateInstance (name, namespace, labels) |  |  |
| `helm` _[HelmSpec](#helmspec)_ | Helm renders a Helm chart instead of a raw Go template.<br />Exactly one of `gotemplate` or `helm` must be specified. |  | Optional: \{\} <br /> |
| `parameters` _[TemplateParameterDefinition](#templateparameterdefinition) array_ | Parameters define the inputs required to render the template.<br />Rules:<br />- `type` is a hint used for validation/coercion (operator-defined). |  | Optional: \{\} <br /> |
| `targetNamespaces` _[TargetNamespaces](#targetnamespaces)_ | TargetNamespaces controls where this Template may be instantiated.<br />Default behavior:<br />If this field is omitted entirely, the Template may ONLY be instantiated<br />in the same namespace as this Template.<br />A namespace is eligible if it matches the explicit list OR the selector. |  | Optional: \{\} <br /> |
| `sync` _[SyncConfig](#syncconfig)_ | Sync controls drift protection for rendered resources. |  | Optional: \{\} <br /> |

#### HelmSpec

HelmSpec defines a Helm chart source and rendering configuration.

_Appears in:_

- [TemplateSpec](#templatespec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `chart` _[HelmChart](#helmchart)_ | Chart defines where the Helm chart is sourced from. |  | Required: \{\} <br /> |
| `releaseName` _string_ | ReleaseName is the Helm release name used during rendering.<br />If omitted, defaults to the TemplateInstance name at render time. |  | MaxLength: 53 <br />Optional: \{\} <br /> |
| `version` _[HelmVersion](#helmversion)_ | Version selects the Helm rendering engine.<br />Defaults to "v4" if omitted. | v4 | Enum: [v3 v4] <br />Optional: \{\} <br /> |
| `valuesTemplate` _string_ | ValuesTemplate is a Go template that renders into YAML used as Helm values.<br />The rendered YAML is parsed and passed as Helm value overrides<br />(merged over the chart's default values.yaml).<br />Available context (same as gotemplate):<br />- .parameters : resolved parameter values<br />- .instance   : metadata of the TemplateInstance (name, namespace, labels) |  | Optional: \{\} <br /> |

#### HelmChart

HelmChart identifies a Helm chart source.

_Appears in:_

- [HelmSpec](#helmspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `repository` _[HelmRepository](#helmrepository)_ | Repository defines the repository location, chart name, version,<br />and optional authentication. |  | Required: \{\} <br /> |

#### HelmRepository

HelmRepository defines the location, chart identity, and optional authentication
for a Helm chart repository or OCI registry.

_Appears in:_

- [HelmChart](#helmchart)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `url` _string_ | URL is the repository URL.<br />For HTTP/HTTPS repositories: <https://charts.example.com><br />For OCI registries: oci://ghcr.io/org/charts |  | MinLength: 1 <br />Pattern: `^(https?\|oci)://` <br />Required: \{\} <br /> |
| `name` _string_ | Name is the chart name within the repository. |  | MinLength: 1 <br />Required: \{\} <br /> |
| `version` _string_ | Version is the exact chart version to pull (SemVer 2, e.g. "1.2.3").<br />Must follow SemVer 2 (<https://semver.org>): MAJOR.MINOR.PATCH with<br />optional pre-release and build metadata. |  | MinLength: 5 <br />Pattern: `^v?(0\|[1-9][0-9]*)\.(0\|[1-9][0-9]*)\.(0\|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$` <br />Required: \{\} <br /> |
| `auth` _[HelmAuth](#helmauth)_ | Auth provides optional authentication credentials.<br />The referenced Secret MUST live in the same namespace as this Template.<br />Supported credential layouts by source type:<br />1. HTTP(S) Helm repositories<br />   - username / password keys<br />   - token key<br />2. OCI registries (oci://)<br />   - username / password<br />   - token<br />   - or standard Docker config (.dockerconfigjson) |  | Optional: \{\} <br /> |

#### HelmAuth

HelmAuth references a Secret containing repository credentials.

_Appears in:_

- [HelmRepository](#helmrepository)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `secretRef` _[SecretRef](#secretref)_ | SecretRef references a Secret in the same namespace as the Template. |  | Required: \{\} <br /> |

#### SecretRef

SecretRef is a reference to a Secret by name.

_Appears in:_

- [HelmAuth](#helmauth)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `name` _string_ | Name of the Secret. |  | MinLength: 1 <br />Required: \{\} <br /> |

#### HelmVersion

_Underlying type:_ _string_

HelmVersion specifies which Helm SDK to use for rendering.

_Validation:_

- Enum: [v3 v4]

_Appears in:_

- [HelmSpec](#helmspec)

| Field | Description |
| --- | --- |
| `v3` |  |
| `v4` |  |

#### TemplateParameterDefinition

TemplateParameterDefinition defines a single parameter for the template.

_Appears in:_

- [TemplateSpec](#templatespec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `name` _string_ | Name is the name of the parameter |  | MinLength: 1 <br />Required: \{\} <br /> |
| `value` _string_ | Option 1 (literal): string\|number\|bool<br />Value provides a literal parameter value (string, number, or bool). |  | Optional: \{\} <br /> |
| `type` _[ParameterType](#parametertype)_ | Type declares the expected type for validation of both template<br />default values and instance overrides. |  | Enum: [string number bool] <br />Optional: \{\} <br /> |
| `required` _boolean_ | Required, if true, means the TemplateInstance MUST provide a value<br />for this parameter, regardless of whether the template has a default. |  | Optional: \{\} <br /> |
| `exposeInStatus` _boolean_ | ExposeInStatus controls whether the resolved value appears in<br />TemplateInstance status resolvedParameters. Defaults to false (hidden). |  | Optional: \{\} <br /> |
| `disableOverride` _boolean_ | DisableOverride controls whether a TemplateInstance may supply its own<br />value for this parameter. Defaults to false (allow override) when omitted. |  | Optional: \{\} <br /> |

#### ParameterType

_Underlying type:_ _string_

ParameterType declares the expected type for validation.

_Validation:_

- Enum: [string number bool]

_Appears in:_

- [TemplateParameterDefinition](#templateparameterdefinition)

| Field | Description |
| --- | --- |
| `string` |  |
| `number` |  |
| `bool` |  |

#### TargetNamespaces

TargetNamespaces defines namespace restrictions for Template instantiation

_Appears in:_

- [TemplateSpec](#templatespec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `explicit` _AllowDeny_ | Explicit defines allowed (and in future, denied) consumer namespaces<br />where this Template may be instantiated. |  | Optional: \{\} <br /> |
| `selector` _[LabelSelector](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.30/#labelselector-v1-meta)_ | Selector dynamically selects namespaces via labels. |  | Optional: \{\} <br /> |

#### SyncConfig

SyncConfig controls drift protection for rendered resources.

_Appears in:_

- [TemplateSpec](#templatespec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `mode` _[SyncMode](#syncmode)_ | Mode selects the drift protection strategy.<br />- off (default): resources are created once with no ongoing enforcement.<br />- revert: the controller continuously reconciles rendered resources,<br />  reverting external drift back to the desired state.<br />- strict: same as revert, plus an admission webhook proactively blocks<br />  unauthorized UPDATE/DELETE on rendered resources. | off | Enum: [off revert strict] <br />Optional: \{\} <br /> |
| `ignoreFields` _string array_ | IgnoreFields defines field paths that are exempt from enforcement.<br />Changes to these fields are allowed even when sync is enabled.<br />Field paths use dot-separated notation and are evaluated per rendered object.<br />Array wildcards are supported via [_] notation.<br />Examples: "metadata.annotations", "spec.replicas", "spec.template.spec.containers[_].env" |  | Optional: \{\} <br /> |

#### SyncMode

_Underlying type:_ _string_

SyncMode controls the level of drift protection for rendered resources.

_Validation:_

- Enum: [off revert strict]

_Appears in:_

- [SyncConfig](#syncconfig)

| Field | Description |
| --- | --- |
| `off` | SyncModeOff disables drift protection. Resources are created once<br />with no ongoing reconciliation or enforcement.<br /> |
| `revert` | SyncModeRevert enables reconciliation-based drift correction.<br />The controller continuously reconciles rendered resources to the<br />desired state, reverting any drift. No webhook enforcement.<br /> |
| `strict` | SyncModeStrict enables reconciliation and webhook enforcement.<br />In addition to continuous reconciliation, an admission webhook<br />proactively blocks unauthorized UPDATE/DELETE on rendered resources.<br /> |

#### TemplateStatus

TemplateStatus defines the observed state of Template.

_Appears in:_

- [Template](#template)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `observedGeneration` _integer_ | observedGeneration is the last generation of the Template<br />that has been processed by the controller. |  | Optional: \{\} <br /> |
| `phase` _[TemplatePhase](#templatephase)_ | phase summarizes the overall validation state of the Template.<br />Typical values: Valid, Invalid, Error |  | Enum: [Valid Invalid Error] <br />Optional: \{\} <br /> |
| `conditions` _[Condition](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.30/#condition-v1-meta) array_ | conditions describe fine-grained validation and availability states<br />following standard Kubernetes condition conventions. |  | Optional: \{\} <br /> |

#### TemplatePhase

_Underlying type:_ _string_

TemplatePhase represents the validation state of a Template.

_Validation:_

- Enum: [Valid Invalid Error]

_Appears in:_

- [TemplateStatus](#templatestatus)

| Field | Description |
| --- | --- |
| `Valid` |  |
| `Invalid` |  |
| `Error` |  |

#### TemplateInstance

TemplateInstance represents a consumer's request to instantiate a Template.
It creates actual Kubernetes resources in the consumer's namespace by rendering
the referenced Template with provided or overridden parameters.

Namespace Scope (Consumer):
The TemplateInstance is created in a consumer namespace.
Any instance-provided overrides that read from ConfigMaps, Secrets, or other resources
are resolved from the namespace specified in the KeyRef or ObjectFieldRef.
When a KeyRef omits the namespace, it defaults to the TemplateInstance's namespace.

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `apiVersion` _string_ | `templates.v2.stakater.com/v2alpha1` | | |
| `kind` _string_ | `TemplateInstance` | | |
| `metadata` _[ObjectMeta](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.30/#objectmeta-v1-meta)_ | Refer to Kubernetes API documentation for fields of `metadata`. |  |  |
| `spec` _[TemplateInstanceSpec](#templateinstancespec)_ |  |  |  |
| `status` _[TemplateInstanceStatus](#templateinstancestatus)_ |  |  | Optional: \{\} <br /> |

#### TemplateInstanceSpec

TemplateInstanceSpec defines the desired state of TemplateInstance.

_Appears in:_

- [TemplateInstance](#templateinstance)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `templateRef` _[TemplateReference](#templatereference)_ | templateRef points to the provider-scoped Template to instantiate.<br />This is a cross-namespace reference by design |  |  |
| `parameters` _[TemplateParameter](#templateparameter) array_ | Parameters override the parameters defined in the referenced Template.<br />Validation:<br />- A parameter override is only allowed if the corresponding Template parameter has<br />  `disableOverride: false` set (or omitted, since it defaults to false).<br />- If a parameter is not overridden here, the Template's default definition is used. |  | Optional: \{\} <br /> |

#### TemplateReference

TemplateReference defines the Template to instantiate

_Appears in:_

- [TemplateInstanceSpec](#templateinstancespec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `name` _string_ | Name of the Template resource |  |  |
| `namespace` _string_ | Namespace where the Template resource is located |  |  |

#### TemplateParameter

TemplateParameter defines a single parameter for TemplateInstance overrides.

_Appears in:_

- [TemplateInstanceSpec](#templateinstancespec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `name` _string_ | Name is the name of the parameter |  | MinLength: 1 <br />Required: \{\} <br /> |
| `value` _string_ | Option 1 (literal): string\|number\|bool<br />Value provides a literal parameter value (string, number, or bool). |  | Optional: \{\} <br /> |
| `valueFrom` _[ValueFrom](#valuefrom)_ | Option 2: read a value dynamically from a cluster resource.<br />Exactly one of `value` or `valueFrom` must be set. |  | MaxProperties: 1 <br />MinProperties: 1 <br />Optional: \{\} <br /> |
| `defaultValue` _string_ | DefaultValue is used when `valueFrom` fails.<br />Only valid with valueFrom. |  | Optional: \{\} <br /> |

#### ValueFrom

ValueFrom specifies a dynamic source for a parameter value.

Exactly one sub-field must be set.

_Validation:_

- MaxProperties: 1
- MinProperties: 1

_Appears in:_

- [ResolvedParameter](#resolvedparameter)
- [TemplateParameter](#templateparameter)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `secretKeyRef` _[KeyRef](#keyref)_ | SecretKeyRef reads a key from a Secret. |  | Optional: \{\} <br /> |
| `configMapKeyRef` _[KeyRef](#keyref)_ | ConfigMapKeyRef reads a key from a ConfigMap. |  | Optional: \{\} <br /> |
| `objectFieldRef` _[ObjectFieldRef](#objectfieldref)_ | ObjectFieldRef reads a field via JSONPath from an arbitrary resource. |  | Optional: \{\} <br /> |

#### KeyRef

KeyRef references a specific key in a Secret or ConfigMap.

_Appears in:_

- [ValueFrom](#valuefrom)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `name` _string_ | Name of the Secret or ConfigMap. |  | MinLength: 1 <br />Required: \{\} <br /> |
| `key` _string_ | Key within the Secret or ConfigMap data to read. |  | MinLength: 1 <br />Required: \{\} <br /> |
| `namespace` _string_ | Namespace of the Secret or ConfigMap.<br />When omitted, defaults to the TemplateInstance's namespace. |  | Optional: \{\} <br /> |

#### ObjectFieldRef

ObjectFieldRef reads a field from an arbitrary Kubernetes resource via JSONPath.

The operator watches the target GVK for change detection.
When Name is set, the operator GETs that specific resource.
When Name is omitted, the operator LISTs all resources of the given GVK
and evaluates JSONPath over the list result.
RBAC: requires get, list, and watch on the target resource.

Namespace scoping:

- Set: operate in that namespace only
- Empty: for namespaced resources, operates across all namespaces;
    for cluster-scoped resources (Nodes, PVs, etc.), ignored

_Appears in:_

- [ValueFrom](#valuefrom)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `apiVersion` _string_ | APIVersion of the target resource (e.g., "networking.k8s.io/v1"). |  | MinLength: 1 <br />Required: \{\} <br /> |
| `kind` _string_ | Kind of the target resource (e.g., "Ingress"). |  | MinLength: 1 <br />Required: \{\} <br /> |
| `name` _string_ | Name of the target resource. When omitted, the operator LISTs all<br />resources of this GVK and evaluates JSONPath over the list result. |  | Optional: \{\} <br /> |
| `namespace` _string_ | Namespace of the target resource.<br />When empty, namespaced resources are listed across all namespaces;<br />cluster-scoped resources ignore this field. |  | Optional: \{\} <br /> |
| `jsonPath` _string_ | JSONPath expression to extract the value (without curly braces).<br />Must start with a dot (e.g., ".metadata.name", not "\{.metadata.name\}").<br />Examples: .status.loadBalancer.ingress[0].ip, .metadata.name, .items[*].metadata.name |  | MinLength: 1 <br />Required: \{\} <br /> |

#### TemplateInstanceStatus

TemplateInstanceStatus defines the observed state of TemplateInstance.

_Appears in:_

- [TemplateInstance](#templateinstance)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `observedGeneration` _integer_ | observedGeneration represents the .metadata.generation that the controller last successfully reconciled. |  | Optional: \{\} <br /> |
| `phase` _[TemplateInstancePhase](#templateinstancephase)_ | phase summarizes the overall validation state of the Template. |  | Enum: [Ready Failed] <br />Optional: \{\} <br /> |
| `resolvedParameters` _[ResolvedParameter](#resolvedparameter) array_ | resolvedParameters exposes the final parameter values used for rendering<br />AFTER merging Template defaults and Instance overrides. |  | Optional: \{\} <br /> |
| `renderedResources` _[ResourceReference](#resourcereference) array_ | renderedResources list the resources created by this TemplateInstance.<br />IMPORTANT:<br />This list contains ONLY the minimum identifying information required<br />to locate the rendered resources (apiVersion, kind, name, namespace).<br />It MUST NOT be treated as a source of truth for desired or live state,<br />and MUST NOT embed full object specs or status. |  | MaxItems: 500 <br />Optional: \{\} <br /> |
| `trackedGVKs` _string array_ | trackedGVKs is the set of GroupVersionKinds this TemplateInstance has rendered. |  | Optional: \{\} <br /> |
| `resolvedTemplateRef` _[ResolvedTemplateRef](#resolvedtemplateref)_ | resolvedTemplateRef shows the exact Template used for rendering,<br />including its namespace and resourceVersion. |  | Optional: \{\} <br /> |
| `conditions` _[Condition](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.30/#condition-v1-meta) array_ | conditions represent the latest available observations of the TemplateInstance's state. |  | Optional: \{\} <br /> |

#### TemplateInstancePhase

_Underlying type:_ _string_

_Validation:_

- Enum: [Ready Failed]

_Appears in:_

- [TemplateInstanceStatus](#templateinstancestatus)

| Field | Description |
| --- | --- |
| `Ready` |  |
| `Failed` |  |

#### ResolvedParameter

ResolvedParameter records the source and optionally the value used for a parameter
after merging Template defaults and Instance overrides.

_Appears in:_

- [TemplateInstanceStatus](#templateinstancestatus)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `name` _string_ | Name of the parameter. |  |  |
| `value` _string_ | Value is the resolved parameter value. Only populated when the<br />Template parameter has exposeInStatus: true. |  | Optional: \{\} <br /> |
| `valueFrom` _[ValueFrom](#valuefrom)_ | ValueFrom records the source that was used to resolve this parameter,<br />when the value came from a dynamic source (secret, configmap, resource). |  | MaxProperties: 1 <br />MinProperties: 1 <br />Optional: \{\} <br /> |

#### ResourceReference

_Appears in:_

- [TemplateInstanceStatus](#templateinstancestatus)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `apiVersion` _string_ | apiVersion of the resource (e.g., "v1", "apps/v1") |  | MinLength: 1 <br />Required: \{\} <br /> |
| `kind` _string_ | kind of the resource (e.g, "ConfigMap, "Deployment") |  | MinLength: 1 <br />Required: \{\} <br /> |
| `name` _string_ | name of the resource |  | MaxLength: 253 <br />MinLength: 1 <br />Required: \{\} <br /> |
| `namespace` _string_ | namespace of the resource |  | MaxLength: 63 <br />Optional: \{\} <br /> |
| `observedGeneration` _integer_ | observedGeneration is the metadata.generation of this resource<br />at the time it was last successfully applied by the controller. |  | Optional: \{\} <br /> |
| `status` _[ResourceReferenceStatus](#resourcereferencestatus)_ | status indicates the health of this resource. Empty means successfully applied. |  | Enum: [ Failed] <br />Optional: \{\} <br /> |

#### ResourceReferenceStatus

_Underlying type:_ _string_

ResourceReferenceStatus indicates the health of a rendered resource.

_Validation:_

- Enum: [ Failed]

_Appears in:_

- [ResourceReference](#resourcereference)

| Field | Description |
| --- | --- |
| `` |  |
| `Failed` |  |

#### ResolvedTemplateRef

ResolvedTemplateRef shows the exact Template used for rendering,
including its namespace and generation.

_Appears in:_

- [TemplateInstanceStatus](#templateinstancestatus)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `name` _string_ | Name of the Template resource |  |  |
| `namespace` _string_ | Namespace where the Template resource is located |  |  |
| `generation` _integer_ | Generation of the Template which increments on spec changes |  |  |
