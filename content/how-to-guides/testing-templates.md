# Testing Templates

A `Template`'s gotemplate is code, and it is rendered by the operator — not by Helm and not by your shell. Test it the way the operator runs it, so a template that passes your tests behaves the same on the cluster. Four layers, each catching what the one above structurally cannot.

| Layer | Needs | Catches |
|-------|-------|---------|
| Chart/YAML lint | nothing | malformed `Template` YAML |
| Render tests | Go, no cluster | wrong rendered output, over any input you choose |
| Admission tests | `envtest` + the CRDs | `Template`/`TemplateInstance` the API server would reject (schema + CEL) |
| End-to-end | a kind cluster + the operator | what actually happens once resources are applied |

## Render tests: use the operator's engine, not Helm

The operator renders with Go `text/template` plus Sprig's `TxtFuncMap` **minus `env`, `expandenv`, `getHostByName`**, and with the `missingkey=error` option. Helm is different — it adds `toYaml`/`include`/`tpl`/`.Files` and replaces `fromJson`/`toJson` — so a gotemplate can pass under Helm and fail on the cluster. Mirror the operator's engine exactly:

```go
package render

import (
    "bytes"
    "text/template"

    "github.com/Masterminds/sprig/v3"
)

// funcs mirrors the operator's function map: Sprig minus the three removed for safety.
func funcs() template.FuncMap {
    f := sprig.TxtFuncMap()
    delete(f, "env")
    delete(f, "expandenv")
    delete(f, "getHostByName")
    return f
}

// Render executes a gotemplate the way the operator does.
func Render(src string, params map[string]any) (string, error) {
    t, err := template.New("t").Funcs(funcs()).Option("missingkey=error").Parse(src)
    if err != nil {
        return "", err
    }
    var out bytes.Buffer
    ctx := map[string]any{"parameters": params, "instance": map[string]any{"name": "x", "namespace": "x"}}
    err = t.Execute(&out, ctx)
    return out.String(), err
}
```

`missingkey=error` is the part a Helm-based test would miss — see [missing keys are an error](../concepts/gotemplate.md#missing-keys-are-an-error) and [this is Sprig, not Helm](../concepts/gotemplate.md#syntax).

Then table-drive it against the shapes your inputs really take — an object with the key present, absent, and `null`; an empty LIST; a value a consumer controls:

```go
func TestRender(t *testing.T) {
    cases := []struct{ name string; params map[string]any; wantErr bool }{
        {"has label", map[string]any{"ns": map[string]any{"metadata": map[string]any{"labels": map[string]any{"team": "a"}}}}, false},
        {"no labels", map[string]any{"ns": map[string]any{"metadata": map[string]any{}}}, false},   // must not panic/err
    }
    for _, tc := range cases {
        t.Run(tc.name, func(t *testing.T) {
            _, err := Render(src, tc.params)
            if (err != nil) != tc.wantErr {
                t.Fatalf("err=%v want %v", err, tc.wantErr)
            }
        })
    }
}
```

A test that cannot fail proves nothing: break a guard on purpose and confirm the matching case goes red.

## Admission tests: will the API server accept the CR?

Render tests prove the *output* is right; they do not prove the `Template` or `TemplateInstance` CR will be accepted. Stand up an API server with [`envtest`](https://book.kubebuilder.io/reference/envtest.html), install the operator's CRDs, and apply the objects your chart produces. This catches structural-schema violations and the CEL rules on the CRDs that only the API server enforces. Vendor the CRDs at the operator version you support, and refresh them when you upgrade (see [Versioning and compatibility](../reference/versioning-and-compatibility.md)).

## End-to-end: run it against the operator

Finally, run on a kind cluster with the operator installed: apply the `Template` and `TemplateInstance`, wait for `Ready`, and assert on what was rendered and on the `status` ([outputs](../concepts/outputs.md), [conditions](../concepts/status.md)). This is the only layer that exercises apply, drift ([sync](../concepts/sync.md)) and cleanup ([lifecycle](../concepts/lifecycle.md)).

## See also

- [Gotemplate](../concepts/gotemplate.md) — the engine and its gotchas.
- [Parameter validation](./parameter-validation.md) — declaring types and required/locked parameters so bad input is rejected early.
- [Versioning and compatibility](../reference/versioning-and-compatibility.md) — pinning the version you test against.
