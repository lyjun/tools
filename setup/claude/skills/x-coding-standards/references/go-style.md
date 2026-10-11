# Go Style Guide

Idiomatic Go patterns and production-quality coding standards. **Explicit is better than implicit** — prefer clarity over cleverness, avoid hidden behaviors and magic.

Based on [Effective Go](https://go.dev/doc/effective_go), [Uber Go Style Guide](https://github.com/uber-go/guide), and [Go Code Review Comments](https://go.dev/wiki/CodeReviewComments).

## Quick Reference

| Pattern | When to Use |
|---------|-------------|
| **Interface compliance** | Verify type implements interface at compile time |
| **Zero-value mutexes** | Don't initialize mutex fields in constructors |
| **Copy at boundaries** | Return copies of slices/maps from exported methods |
| **Enums start at one** | Zero value = unknown/invalid |
| **Nil slices over empty** | Use `var s []T` not `s := []T{}` |
| **Pass values** | Don't use pointers just to save bytes |

## Production Guidelines

### 1. Verify Interface Compliance at Compile Time

```go
type Handler struct{}

var _ http.Handler = (*Handler)(nil)  // Fails to compile if method missing

func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
    // ...
}
```

### 2. Pointers to Interfaces — Usually Don't

```go
// Good: Interface as value
func ProcessData(r io.Reader) ([]byte, error) {
    return io.ReadAll(r)
}

// Bad: Pointer to interface (rarely needed)
func ProcessData(r *io.Reader) ([]byte, error) {
    return io.ReadAll(*r)
}
```

Interfaces already contain pointers internally. Double pointers add unnecessary complexity.

### 3. Zero-Value Mutexes Are Valid

```go
type Cache struct {
    mu   sync.Mutex          // zero-value is ready to use
    data map[string]string
}

func NewCache() *Cache {
    return &Cache{
        data: make(map[string]string),  // mu needs no initialization
    }
}
```

Don't embed mutexes — use named fields so they're not accidentally exported.

### 4. Copy Slices and Maps at Boundaries

```go
// Good: Return a copy
func (u *User) GetTags() []string {
    tags := make([]string, len(u.tags))
    copy(tags, u.tags)
    return tags  // Caller can't modify u.tags
}

// Bad: Returning internal reference
func (u *User) GetTags() []string {
    return u.tags  // Caller can modify internal state
}
```

### 5. Start Enums at One

```go
type Status int

const (
    StatusUnknown Status = iota  // = 0 (invalid/unknown)
    StatusPending                // = 1
    StatusActive                 // = 2
)
```

Exception: Zero value is desirable default (e.g., `LogToStdout`).

### 6. Handle Type Assertion Failures

```go
// Good: Two-value form
t, ok := i.(string)
if !ok {
    // handle gracefully
}

// Bad: Single-value form panics on failure
t := i.(string)
```

### 7. Avoid Mutable Globals

```go
// Bad: Mutable global
var db *sql.DB

// Good: Dependency injection
type Server struct {
    db *sql.DB
}

func NewServer(db *sql.DB) *Server {
    return &Server{db: db}
}
```

### 8. Avoid Embedding Types in Public Structs

```go
// Bad: Leaks embedded type's methods
type Client struct {
    http.Client  // All http.Client methods are exported
}

// Good: Explicit delegation
type Client struct {
    client http.Client
}

func (c *Client) Do(req *http.Request) (*http.Response, error) {
    return c.client.Do(req)
}
```

**Exception in test code:** embed an interface as a stub so only methods under test need real implementations.

### 9. Avoid `init()`

Prefer explicit initialization. If `init()` is unavoidable:
- Must be deterministic (no I/O, no env vars)
- Must not depend on ordering with other `init()` functions
- No goroutines in `init()`

### 10. Exit in Main

Call `os.Exit` or `log.Fatal` only in `main()`. Other functions return errors.

```go
func main() {
    if err := run(); err != nil {
        log.Fatal(err)
    }
}

func run() error {
    // all logic here, returns errors
}
```

### 11. Declare Nil Slices, Not Empty

```go
// Good: nil slice (preferred)
var t []string           // nil, len=0, encodes to JSON null

// Bad: empty slice (use only when non-nil matters)
t := []string{}          // non-nil, len=0, encodes to JSON []
t := make([]string, 0)   // same as above
```

Nil slices are functionally equivalent for `len`, `cap`, `append`, and `for range`. Use empty slice only when the distinction matters (e.g., JSON encoding).

### 12. Pass Values, Not Pointers (Unless Needed)

```go
// Good: pass by value for small structs
func Distance(p1, p2 Point) float64 {
    return math.Hypot(p1.X-p2.X, p1.Y-p2.Y)
}

// Bad: unnecessary pointer for small immutable data
func Distance(p1, p2 *Point) float64 {
    return math.Hypot(p1.X-p2.X, p1.Y-p2.Y)
}
```

Use pointers only when: method needs to modify receiver, struct is large, or semantics require shared identity.

## Comments

**Language:** All code comments MUST be in English. No Chinese or other non-English languages in comments.

**Doc comments** (before exported identifiers, no blank lines):
```go
// Reader reads from an input source.
type Reader struct { ... }
```

**Regular comments** (explain why, not what):
```go
// Avoid division by zero
if denominator == 0 {
    return 0, ErrDividingByZero
}
```

**Special markers:**

| Marker | Purpose | Format |
|--------|---------|--------|
| `TODO` | Planned improvement | `// TODO: <description>` |
| `FIXME` | Known bug or incorrect implementation | `// FIXME: <description>` |
| `XXX` | Serious issue, hacky workaround | `// XXX: <warning and explanation>` |

If the issue can be fixed immediately, fix it instead of leaving a marker.

## Style Essentials

**Naming:**
- **MixedCaps/mixedCaps**, never snake_case
- **Acronyms** all caps: `HTTP`, `URL`, `ID`, `API`
- **Variables:** short in small scopes (`i`, `n`, `err`), descriptive in larger scopes
- **Constants:** MixedCaps, not `ALL_CAPS` (e.g., `MaxRetries`)
- **Interfaces:** single-method interfaces end in `-er` (`Reader`, `Writer`)
- **Function names:** no `Get` prefix for getters; `SetField` for setters
- **Package names:** lowercase, single-word, no underscores
- **Package comments:** `// Package foo ...` before package clause; one file per package suffices

**Code Organization:**
- One main concept per file; order: constants/vars → types → constructors → methods → helpers
- **Constants & package-level vars** go after the import block, before the first function — never scattered between functions
- **Import groups:** stdlib, external, internal (separated by blank lines)
- **Import blank (`_`):** only in `main` package or test files for side effects
- **Import dot (`.`):** don't use; exception: test files with circular dependency
- **Import aliasing:** only when names conflict

**Function Signatures:**
- Context as first parameter, error as last return value
- Never store Context in a struct; pass explicitly through call chain
- Limit to 3-4 parameters; use structs for more

**Receivers:**
- Short names (1-2 characters), consistent across all methods of a type
- Pointer receivers when method modifies receiver or struct is large
- Value receivers for small, immutable types
- Be consistent: if any method uses pointer, all should

**Readability:**
- **Line length:** avoid overly long lines; break at natural points
- **Reduce nesting:** early returns, continue in loops, happy path left-aligned
- **Naked parameters:** use comments for ambiguous bool/int args

```go
// Bad: what do these mean?
db.Connect(true, false)

// Good: clarify with comments or named types
db.Connect(/*master=*/true, /*readOnly=*/false)
```

## Code Review Checklist

- Functions are under 50 lines
- Naming follows conventions (exported = PascalCase, unexported = camelCase)
- Errors are handled explicitly, not ignored
- Defer is used for cleanup (files, locks, etc.)
- Early returns eliminate unnecessary nesting
- Comments explain why, not what
- Interfaces are small (1-3 methods)
- Methods use consistent receiver names
- No fire-and-forget goroutines
- Slices/maps copied at API boundaries
