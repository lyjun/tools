# Helm Chart Rules

## Standard Kubernetes Labels

Every chart's `_helpers.tpl` must include these labels (via a shared `labels` template):

- `app.kubernetes.io/name` — chart name
- `app.kubernetes.io/instance` — release name
- `app.kubernetes.io/managed-by` — `{{ .Release.Service }}`
- `helm.sh/chart` — chart name + version

## Template Quality

- **Input validation**: Use `fail()` to validate required values and file existence before rendering. Silent `<no value>` output masks bugs
- **Unused loop variables**: Use `range $item` not `range $_, $item` — Go templates don't require a blank identifier for unused index
- **Avoid redundant calls**: Extract repeated template function results (e.g., `.Files.Get`) into a variable with `$var := ...`

## Chart Completeness

New charts must include:

| File | Purpose |
|------|---------|
| `values.schema.json` | JSON Schema for Helm values validation |
| `tests/` (helm-unittest) | At least basic rendering + metadata tests |
| `.helmignore` | Exclude `tests/` from packaged chart |

## Values Design

- Default to empty/safe values (e.g., `prometheusRules: []`) so the chart installs without error
- Use `omitempty` / conditional blocks for optional sections
- Document required vs optional values in `values.yaml` comments
