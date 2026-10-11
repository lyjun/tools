# Go Lint

## Overview

Fix linter issues through code changes. `// nolint` is the last resort, not the first.

## Validation Workflow

```bash
# With Makefile (preferred)
make lint && make test        # golangci-lint run; go test -race ./...
make lint-fix                 # golangci-lint run --fix — applies every auto-fixable issue
make lint-config              # golangci-lint config verify — run after editing .golangci.yml

# Without Makefile
golangci-lint run && go test -race ./...
```

`make lint` and `make test` must both pass before considering work complete.

## Formatting Is Enforced by `make lint`

Configs are golangci-lint v2 (`version: "2"` at the top of `.golangci.yml`), where formatters live in a `formatters:` block and run as part of `golangci-lint run`. Read that block to see which formatter the repo uses — most enable **gofumpt**, which is stricter than gofmt, so a file `gofmt -l` calls clean still fails the lint gate:

```
main.go:8:1: File is not properly formatted (gofumpt)
```

`make fmt` (`go fmt ./...`) does not fix gofumpt-only violations — an empty line opening a block, for example, survives it. Use `make lint-fix`, or `golangci-lint fmt` to reformat without running the linters.

## `// nolint` Rules

### Prohibited

```go
//nolint                    — blanket suppression, forbidden
//nolint:errcheck           — suppression without justification, forbidden
```

### Allowed (only these three cases)

**1. False positive** — linter is wrong despite correct code:
```go
// False positive: variable is accessed via reflection, linter cannot see it
var registeredHandlers = map[string]Handler{} //nolint:unused
```

**2. Intentional violation with documented justification:**
```go
// Complex state machine: each branch represents a distinct protocol state.
// Extracting sub-functions would obscure the state transitions.
func (sm *StateMachine) Transition(event Event) State { //nolint:gocyclo
```

**3. Test code exception** — intentional rule violation inside a test:
```go
_ = os.Remove(tmpFile) //nolint:errcheck // Cleanup in test teardown; failure here is non-critical
```

### Required Format

Every `// nolint` must be preceded by a comment that explains why:

```go
// <Why the issue cannot be fixed normally>
// <What the preferred solution would be, and why it's blocked>
statement() //nolint:<specific-linter> // brief reason
```

**Always name specific linters** — `//nolint:gocyclo` not `//nolint`.

### Standard Process

1. Run `make lint` — identify all issues
2. Fix through code changes (always first choice)
3. If suppression is truly necessary:
   - Add explanation comment above
   - Name the specific linter
   - Flag for code review
4. Never suppress as a substitute for refactoring

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| `//nolint` with no linter name | Name the specific linter |
| No comment above `//nolint` | Add explanation of why fix isn't possible |
| Suppressing in production code to meet a deadline | Fix the code; create a tracked issue if deferred |
| Bulk-suppressing a file with `//nolint:all` | Fix each violation individually |
