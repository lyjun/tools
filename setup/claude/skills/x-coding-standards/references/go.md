# Go Project Rules

## Principles

- **Target First**: Confirm deployment target. Don't over-split files for cross-platform
- **Probe First**: Uncertain about API support → write a test to verify
- **Signature changes**: Update `_test.go` first after changing public function signatures
- **Removed call sites**: After a change drops a function's call site, grep its remaining callers; if all are in the same package's `_test.go` files, move it there — see go-testing.md〈Test-only code lives in `_test.go`〉
- **Interface changes**: Grep all mock implementations (`**/mock*.go`, `*_test.go`) and update ALL before proceeding
  - Also search for **composite interfaces** that embed the changed interface (e.g., changing `SystemdManager` → also search `SystemDbusManager` mocks)
  - Run `go test ./...` before pushing to catch missing implementations
- **Build tags**: `go test ./...` and `go vet ./...` never compile a file behind a build tag that is not enabled (`//go:build integration` or any other tag), so a broken reference there still exits 0 — `go test` even prints `[no test files]`, which reads as "this package is clean". Run the tagged set (`go test -tags=<tag> ./...`) before reporting a package verified
- **Type flexibility**: External APIs (D-Bus/JSON) may return multiple types → use type switch or comma-ok assertion (`v, ok := x.(T)`). **Never** use bare assertion (`v := x.(T)`) — it panics on type mismatch
- **Dependency injection**: Use struct fields + method receivers, not function parameter passing

## Dependency Priority (mandatory)

1. **Project internal**: Search `pkg/` and `internal/` by directory name → read to confirm → must use if found
2. **Standard library**: Only when no internal package exists
3. **Third-party**: Ask user via AskUserQuestion before adding

## New .go File Checklist

Before Write: scan all function calls, categorize imports (stdlib / third-party / internal), verify import block is complete. Common misses: `fmt` for Errorf/Sprintf, `os` for Open/ReadFile, `context` for Context type, internal packages for type references.

## Modern Go (post-training knowledge)

### Go 1.23+

- Iterator functions with `slices` and `maps` packages:

```go
for i, v := range slices.All(items) {
    fmt.Println(i, v)
}

for k := range slices.Sorted(maps.Keys(config)) {
    fmt.Println(k, config[k])
}
```

### Go 1.24+

- `strings.SplitSeq()` / `Lines()` / `FieldsSeq()` for zero-alloc iteration
- JSON `omitzero` for correct zero-value omission where a field should be omitted (struct/scalar → `omitzero`, slice/map → `omitempty`). HTTP response fields are never omitted — see `rest-api.md`
- `tool` directive in go.mod replaces `tools.go` blank import

### Go 1.25+

- `wg.Go(func() { ... })` replaces Add/Done pattern
- `testing/synctest.Test()` for virtual-clock concurrency testing
- Runtime auto-respects cgroup CPU limits (no manual GOMAXPROCS)

### Go 1.26+

- `errors.AsType[T]` for type-safe error extraction:

```go
if pathErr, ok := errors.AsType[*os.PathError](err); ok {
    fmt.Println(pathErr.Path)
}
```

### Modernization with `go fix` (Go 1.24+)

`go fix` auto-rewrites older Go idioms into current ones. Run it after upgrading the toolchain.

```bash
go fix -diff ./...        # preview only — REQUIRED before applying
go fix ./...              # apply all fixers
go fix -slicessort ./...  # apply a single named fixer
```

Common fixers (run `go help fix` for the live list):

| Fixer | Effect |
|-------|--------|
| `minmax` | `if/else` → `min()` / `max()` |
| `slicessort` | `sort.Slice` → `slices.Sort` |
| `slicescontains` | manual loop → `slices.Contains` |
| `stringscut`, `stringscutprefix` | `Index` / `HasPrefix`+`TrimPrefix` → `Cut` / `CutPrefix` |
| `stringsseq` | `strings.Split` loop → `SplitSeq` iterator |
| `rangeint` | 3-clause `for` → `for range N` |
| `testingcontext` | manual `context.WithCancel` → `t.Context()` |
| `waitgroup` | `wg.Add(1)` + `go` + `Done` → `wg.Go()` |
| `any` | `interface{}` → `any` |
| `fmtappendf` | `[]byte(fmt.Sprintf(...))` → `fmt.Appendf` |

After upgrading Go versions, run `go fix -diff ./...` first to inspect the diff, then `go fix ./...` to apply. Do not apply blindly — modernizers occasionally produce semantically equivalent but stylistically surprising rewrites that callers expect to review.

## Structured Logging (log/slog)

Use `log/slog` (Go 1.21+) instead of `log` package:

```go
slog.Info("request handled",
    "method", r.Method,
    "path", r.URL.Path,
    "duration", time.Since(start),
)
```

## Concurrency

### Goroutine Lifecycle

- Every goroutine MUST have a clear exit condition
- Use `context.Context` for cancellation
- The goroutine starter is responsible for ensuring it can be stopped

### Channel Principles

- Unbuffered channel: synchronization (handoff)
- Buffered channel: known work volume or rate limiting
- Sender is responsible for closing the channel

### errgroup with Bounded Concurrency

```go
g, ctx := errgroup.WithContext(ctx)
g.SetLimit(10)

for _, item := range items {
    g.Go(func() error {
        return process(ctx, item)
    })
}

if err := g.Wait(); err != nil {
    return err
}
```

### sync.Map vs Mutex

- `sync.Map`: stable key set, read-heavy workloads
- `sync.Mutex` / `sync.RWMutex`: most other cases

## Error Handling

### Error Wrapping

Use `fmt.Errorf` with `%w` to preserve the error chain:

```go
if err != nil {
    return fmt.Errorf("open config %s: %w", path, err)
}
```

### Sentinel Errors

Package-level known errors use `Err` prefix:

```go
var ErrNotFound = errors.New("not found")
```

### Custom Error Types

Use when errors need to carry additional information:

```go
type ValidationError struct {
    Field   string
    Message string
}

func (e *ValidationError) Error() string {
    return fmt.Sprintf("validation: %s — %s", e.Field, e.Message)
}
```

### Principles

- Handle errors once: either return or log, never both
- Add context (caller, parameters) at system boundaries
- Use `panic` only when the program cannot continue

## Generated File Patterns (auto-generated, not subject to review or modification)

**The list lives in `x-coding-standards/SKILL.md` § Generated & Lock File Exclusions — go there, not here.**

The one Go-specific thing worth repeating here: **the primary test is the content marker, not the filename.** A file whose first lines carry `// Code generated by … DO NOT EDIT.` is generated whatever it is called — that is how sqlc's `db.go` / `models.go` / `querier.go` and deepcopy-gen's `zz_generated.deepcopy.go` get excluded. Do not turn those into filename patterns: 6 of the 56 files named `db.go` / `models.go` / `querier.go` in this workspace are hand-written.

## Proto Response Safety

Proto message getters (e.g., `resp.GetSshConfig()`) return nil when the field is unset. Always nil-check before accessing nested fields:

```go
// Bad: panics if SshConfig is nil
cfg := resp.GetSshConfig()
port := cfg.GetPort()

// Good: guard against nil
cfg := resp.GetSshConfig()
if cfg == nil {
    return nil, fmt.Errorf("unexpected nil SshConfig in response")
}
port := cfg.GetPort()
```

This applies to any proto getter that returns a message type — the outer response succeeding does not guarantee nested messages are populated.

## text/template

- Always use `Option("missingkey=error")` — default behavior silently produces `<no value>` for missing keys, masking bugs
- When a function wraps template parse+execute, callers should reuse it instead of duplicating the template logic

## Security

### Input validation

- Validate all external input at system boundaries
- Use allowlists, not denylists

### Path traversal

- Prefer `os.Root` (Go 1.24+) for filesystem operations scoped to a directory — the root rejects symlink escapes and `..` traversal:

```go
root, err := os.OpenRoot("/var/lib/app/uploads")
if err != nil {
    return err
}
defer root.Close()

f, err := root.Open(userSuppliedPath) // safe — cannot escape /var/lib/app/uploads
```

- When `os.Root` is unavailable (pre-1.24 target), use `filepath.Clean` plus an explicit prefix check. Never concatenate untrusted input into a path without validation.

### Command execution (`os/exec`)

**Decision process:**

1. Search the Go standard library first
2. If unavailable, find a well-maintained Go package
3. Only as last resort: `os/exec`, wrapped behind an executor interface in `internal/cli/<toolname>.go` so tests can mock it and call sites are auditable. Never call `exec.Command` from business logic, and never scatter it across the codebase.

```go
// internal/cli/git.go
type GitClient interface {
    Status(ctx context.Context) (*StatusResult, error)
    Commit(ctx context.Context, message string) error
}

type gitClient struct{ execPath string }

func NewGitClient() GitClient { return &gitClient{execPath: "git"} }
```

**Common alternatives:**

| CLI Tool | Go Alternative |
|----------|----------------|
| `git` | `github.com/go-git/go-git/v5` |
| `docker` | `github.com/docker/docker/client` |
| `kubectl` | `k8s.io/client-go` |
| `curl`/`wget` | `net/http` |
| `jq` | `encoding/json` |
| `tar`/`gzip` | `archive/tar`, `compress/gzip` |
| `openssl` | `crypto/*` |

**Never** build commands by string concatenation with user input. Pass arguments as separate slice elements:

```go
// Good
exec.CommandContext(ctx, "git", "checkout", branch)

// Bad — branch could be `; rm -rf /`
exec.CommandContext(ctx, "sh", "-c", "git checkout "+branch)
```

### Other primitives

- SQL: use parameterized queries, never string-concatenate user input
- Randomness: `crypto/rand` for security-sensitive randomness, `math/rand` is **not** safe
- Constant-time comparison: `crypto/subtle.ConstantTimeCompare` for tokens / MACs
- Log redaction: implement `slog.LogValuer` on types that hold secrets

## Testing

- Test meaningful behavior, not for coverage numbers
- `b.Loop()` for benchmarks, `t.Context()` for auto-cancel, `t.Chdir()` for temp working dir (Go 1.24+)
- Never call `t.Fatal` from goroutines — use `t.Error` instead

---

# Go Idiomatic Patterns

Recurring Go patterns that improve API design, readability, and correctness.

## Quick Reference

| Pattern | When to Use |
|---------|-------------|
| **Functional options** | Truly optional config without parameter explosion |
| **Deps struct** | Group of required dependencies for a component |
| **Named returns + defer** | Tracing, logging, cleanup with result access |
| **If with short init** | Scope variables to conditional block |
| **Accept interfaces, return structs** | Narrow input types, concrete output types |
| **No in-band errors** | Signal errors via return value, not sentinel values |

## Functional Options vs Deps Struct

**Key principle:** Functional options are for **truly optional** configuration. Required dependencies belong in explicit parameters or a Deps struct. Mixing the two disguises mandatory dependencies as optional — callers forget a `With*()` call and only discover the missing dependency at runtime.

| Aspect | Deps Struct | Functional Options (for required deps) |
|--------|-------------|----------------------------------------|
| Compile-time safety | Fields visible, IDE autocomplete | Forgetting `WithX()` only fails at runtime |
| Caller clarity | One glance shows what's needed | N chained `With*` calls are hard to scan |
| Validation | Centralized `Validate()` method | Scattered nil checks |

### Functional Options — for optional configuration

```go
type Option func(*Server)

func WithPort(port int) Option {
    return func(s *Server) { s.port = port }
}

func WithTimeout(t time.Duration) Option {
    return func(s *Server) { s.timeout = t }
}

func NewServer(opts ...Option) *Server {
    s := &Server{port: 8080, timeout: 30 * time.Second}
    for _, opt := range opts {
        opt(s)
    }
    return s
}

// Usage
srv := NewServer(WithPort(9090), WithTimeout(time.Minute))
```

Typical use cases: test path overrides, logger injection, optional behaviors, feature flags.

### Deps Struct — for required dependencies

Use when a component needs multiple collaborators that are all mandatory:

```go
// Deps groups required dependencies — every field must be non-nil.
type Deps struct {
    Logger    *slog.Logger
    Store     Store
    Notifier  Notifier
}

func (d Deps) Validate() error {
    if d.Logger == nil {
        return errors.New("logger is required")
    }
    if d.Store == nil {
        return errors.New("store is required")
    }
    if d.Notifier == nil {
        return errors.New("notifier is required")
    }
    return nil
}

// Required deps as struct, optional config as functional options.
func New(deps Deps, opts ...Option) (*Manager, error) {
    if err := deps.Validate(); err != nil {
        return nil, fmt.Errorf("invalid deps: %w", err)
    }
    m := &Manager{deps: deps}
    for _, opt := range opts {
        opt(m)
    }
    return m, nil
}
```

**Deps struct and functional options are complementary, not competing.** Use Deps for mandatory collaborators; use options for truly optional configuration.

## Named Return Values with Defer

Defer can access and modify named return values:

```go
func BigOperation() (result string, err error) {
    defer func() {
        log.Printf("BigOperation result=%q err=%v", result, err)
    }()
    // ... operation
    return
}
```

**Named result parameters:** Use only when they improve doc clarity or enable defer patterns. Avoid naked returns in functions longer than a few lines — they hurt readability.

## If-Else with Short Initialization

```go
if err := os.Chdir("/path"); err != nil {
    log.Fatal(err)
}

// err silently ignored — only use when failure is truly optional
if file, err := os.Open("file.txt"); err == nil {
    defer file.Close()
    // use file
}

if user := findUser(id); user != nil {
    return user.Email
}
```

## Accept Interfaces, Return Structs

```go
// Good: accept interface for flexibility
func ProcessData(r io.Reader) (*Result, error) {
    data, err := io.ReadAll(r)
    // ...
}

// Bad: accept concrete type unnecessarily
func ProcessData(f *os.File) (*Result, error) { ... }
```

Accept the narrowest interface that satisfies the need. Return concrete types so callers get full functionality.

## Avoid In-Band Errors

```go
// Bad: in-band error value
func Lookup(key string) string {
    return ""  // Is "" a valid value or an error?
}

// Good: separate error return
func Lookup(key string) (string, error) {
    if !exists(key) {
        return "", ErrNotFound
    }
    return value, nil
}

// Good: comma-ok idiom
func Lookup(key string) (string, bool) {
    v, ok := m[key]
    return v, ok
}
```

Don't use special values (-1, nil, "") to signal errors. Use multiple return values.

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Large parameter lists | Use functional options or config struct if > 3-4 params |
| Required deps wrapped as functional options | Use Deps struct for mandatory collaborators; reserve options for truly optional config |
| Named returns with naked `return` in long function | Use named returns only for short functions or defer patterns |
| Returning `""` / `-1` to signal "not found" | Return `(value, bool)` or `(value, error)` |
| Accepting `*os.File` when `io.Reader` suffices | Accept the narrowest interface |
