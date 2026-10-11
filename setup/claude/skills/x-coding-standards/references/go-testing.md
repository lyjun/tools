# Go Testing Patterns

## Overview

Go testing patterns and best practices for writing clear, meaningful, and maintainable tests. Focus on behavior verification, not coverage metrics.

**Core Principles:**
- Tests MUST be clear, meaningful, and maintainable
- Use table-driven tests for multiple similar cases
- Each test should focus on a single behavior
- Coverage metrics are indicators, not goals

**File types:**
- Unit tests: `*_test.go`, no external dependencies, fast (milliseconds)
- Integration tests: `//go:build integration`, run with `go test -tags=integration ./...`

## Quick Reference

| Pattern | When to Use |
|---------|-------------|
| **`require`** | Setup/preconditions — stop immediately on failure |
| **`assert`** | Behavior checks — collect all failures, report together |
| **Table-Driven** | Same validation logic, different input/output data |
| **Separate t.Run()** | Different validation logic, testing distinct behaviors |
| **Hand-Written Mocks** | Interfaces with < 10 methods |
| **Function Fields Mock** | Need flexible per-test behavior control |
| **t.Helper()** | Setup logic repeated in 3+ tests |
| **t.Cleanup()** | Resource allocation/deallocation |
| **t.Parallel()** | Independent tests that can run concurrently |
| **`synctest.Test()`** | Time-dependent or goroutine synchronization tests |
| **`b.Loop()`** | Simple benchmarks (Go 1.24+) |
| **`b.N` loop** | Benchmarks needing per-iteration setup/teardown |

## Assertions

### assert vs require

The most critical decision: **`assert` continues the test, `require` stops it immediately.**

```go
func TestCreateUser(t *testing.T) {
    // require: stop immediately if precondition fails
    user, err := CreateUser(ctx, req)
    require.NoError(t, err)
    require.NotNil(t, user)

    // assert: collect all failures, report together
    assert.Equal(t, "alice", user.Name)
    assert.Equal(t, "alice@example.com", user.Email)
    assert.False(t, user.Disabled)
}
```

**Rules:**
- Use `require` for setup steps and preconditions — when failure makes subsequent assertions meaningless or causes a panic
- Use `assert` for the actual behavior checks — lets you see all failures at once

### Common Assertions

```go
// Equality
assert.Equal(t, expected, actual)          // expected first, always
assert.NotEqual(t, unexpected, actual)

// Nil / existence
assert.Nil(t, err)
assert.NotNil(t, result)

// Errors
assert.NoError(t, err)
assert.Error(t, err)
assert.ErrorIs(t, err, ErrNotFound)        // checks error chain
assert.ErrorAs(t, err, &target)           // extracts typed error

// Collections
assert.Len(t, slice, 3)
assert.Contains(t, slice, item)
assert.Empty(t, slice)
assert.NotEmpty(t, slice)

// Boolean
assert.True(t, condition, "message")
assert.False(t, condition)
```

> **Parameter order:** always `(t, expected, actual)`. Reversing it gives misleading failure messages.

### Error Checking

```go
require.Error(t, err)
assert.ErrorIs(t, err, ErrExpected)    // checks error chain
assert.ErrorAs(t, err, &target)        // extracts typed error
```

**Edge Cases to Test:**
- Nil/empty inputs: `nil`, `""`, `[]`, `map[string]int{}`
- Boundary values: `0`, `-1`, `MaxInt`, `MinInt`
- Out-of-range: negative indices, overflow conditions
- Special cases: duplicate items, single item, very large inputs

## Table-Driven Tests

```go
func TestValidateEmail(t *testing.T) {
    tests := []struct {
        name    string
        email   string
        wantErr bool
    }{
        {"valid", "user@example.com", false},
        {"invalid", "not-an-email", true},
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            err := ValidateEmail(tt.email)
            if tt.wantErr {
                require.Error(t, err)
                return
            }
            require.NoError(t, err)
        })
    }
}
```

**Table-Driven is ideal when:**
- All test cases share identical setup and assertion patterns
- Only input values and expected outputs differ
- Adding new cases requires just one line in the table

**Separate t.Run() is better when:**
- Each subtest verifies different aspects of behavior
- Validation logic varies significantly between cases
- Forcing table structure would require many boolean flags or conditional checks

## Mocking

Use mocking tools only for large interfaces (10+ methods).

**Interface Change Propagation:** Adding or removing methods on a Go interface requires updating all mock structs that implement it, including local mocks in test files. These won't cause git conflicts but will fail to compile.

**Interface Stub (embed interface for partial implementation):**

```go
type mockStorage struct {
    storage.Backend         // satisfies the interface; unimplemented methods panic
    uploadFunc func(context.Context, string, io.Reader) error
}

func (m *mockStorage) Upload(ctx context.Context, key string, r io.Reader) error {
    return m.uploadFunc(ctx, key, r)
}
```

Never use embed stubs in production structs — implement all methods explicitly.

**Function Fields Pattern (Recommended):**

```go
type mockUserRepository struct {
    getByIDFunc func(ctx context.Context, id string) (*User, error)
    saveFunc    func(ctx context.Context, u *User) error
}

func (m *mockUserRepository) GetByID(ctx context.Context, id string) (*User, error) {
    if m.getByIDFunc != nil {
        return m.getByIDFunc(ctx, id)
    }
    return nil, errors.New("getByIDFunc not set")
}

func (m *mockUserRepository) Save(ctx context.Context, u *User) error {
    if m.saveFunc != nil {
        return m.saveFunc(ctx, u)
    }
    return errors.New("saveFunc not set")
}

// Usage in test
func TestCreateUser(t *testing.T) {
    mock := &mockUserRepository{
        saveFunc: func(ctx context.Context, u *User) error {
            if u.Name == "" {
                return errors.New("name required")
            }
            return nil
        },
    }

    service := NewUserService(mock)
    err := service.Create(context.Background(), &User{Name: "John"})
    require.NoError(t, err)
}
```

**Removing an output needs an assertion the old output cannot satisfy.** Asserting only that the remaining outputs are still there passes unchanged when the removal silently did not happen. Prefer asserting the *exact* set (`want exactly [a b]`) over asserting one named item is absent — the absence form still goes green when some third unexpected output appears. Then inject the old behavior once and confirm the assertion goes red: an assertion never seen failing is not known to be checking anything.

**The same red check applies to any test added for a bug fix or to pin a behavior.** Revert the fix (or inject the old behavior; for a test that pins existing behavior, break that behavior in the code under test), run the test, and confirm it fails for the expected reason — the assertion on the behavior under test, not a compile error, a setup `require` failing, or a typo. Then restore the change and confirm it passes. A test that fails for the wrong reason proves only that its setup is broken.

## Test Quality

**Naming Convention:**
- Descriptive names: `TestFunctionName_InputDescription_ExpectedOutcome`
- Subtests: Use clear, non-ambiguous names in `t.Run()`
- Example: `TestParseConfig_InvalidJSON_ReturnsError`

**Independence Principles:**
- Each test must be executable independently, in any order
- **NO** shared state between tests (use separate setup per test)
- Always clean up resources (files, connections, goroutines)
- Tests should not depend on other tests' results

**Using t.Cleanup():**
```go
func TestWithResource(t *testing.T) {
    f := openFile(t, "test.txt")
    t.Cleanup(func() { f.Close() })
    // Use f in test
}
```

**Helper Functions:**
```go
func createTestUser(t *testing.T) *User {
    t.Helper()  // Skip helper in error line numbers
    u := &User{Name: "test"}
    if err := saveUser(u); err != nil {
        t.Fatalf("setup failed: %v", err)
    }
    return u
}
```

**Test-only code lives in `_test.go`:**
- A function in a production file that only tests in the same package call goes in a `_test.go` file of that package. It still sees unexported identifiers, and a reader of the production file no longer takes it for production behavior — a doc comment like "applies Run's checks" on a function `Run` never calls says the opposite of what the code does.
- The usual way one appears is a refactor, not new code: a change removes a function's last production call site while its tests still call it, so the "remove what your change made unused" check never fires. When a change drops a call site, grep the function's remaining callers; if all of them are in the same package's `*_test.go` files, move it.
- Unexporting it is not the fix: the function stays in the production file and still reads as part of the package's behavior.
- An external test package (`package foo_test`) that needs internal access gets an `export_test.go` that re-exports what it needs.
- Does not apply to mocks or test utilities shared across packages (`**/mock*.go`, a `testutil` package): a `_test.go` file cannot be imported, so moving them breaks the other packages' builds.

## Advanced Testing

### Race Detection

```bash
go test -race ./...
go test -race -run TestName
```

`-race` flag MUST pass in CI/CD.

### synctest — Deterministic Concurrent Testing (Go 1.25+)

Runs goroutines in an isolated "bubble" with fake time. Time advances instantly when all goroutines are blocked.

```go
func TestContextTimeout(t *testing.T) {
    synctest.Test(t, func(t *testing.T) {
        ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
        defer cancel()

        time.Sleep(5*time.Second - time.Nanosecond)
        synctest.Wait()
        if ctx.Err() != nil {
            t.Fatal("context expired too early")
        }

        time.Sleep(time.Nanosecond)
        synctest.Wait()
        if ctx.Err() != context.DeadlineExceeded {
            t.Fatal("context should have expired")
        }
    })
}
```

**When to use:** negative assertions, time-dependent logic, goroutine synchronization ordering.
**When NOT to use:** external I/O, real network calls, code depending on real wall-clock time.

### Benchmarking

**`b.Loop()` (Go 1.24+) — Preferred for simple benchmarks:**

```go
func BenchmarkProcess(b *testing.B) {
    for b.Loop() {
        Process(testData)
    }
}
```

**`b.N` — Use when per-iteration setup must be excluded from timing:**

```go
func BenchmarkWithSetup(b *testing.B) {
    for i := 0; i < b.N; i++ {
        b.StopTimer()
        data := generateTestData()
        b.StartTimer()
        Process(data)
    }
}
```

> `b.StopTimer()`/`b.StartTimer()` inside `b.Loop()` causes an infinite loop ([Go#72922](https://github.com/golang/go/issues/72922)). Use the `b.N` pattern instead.

### Fuzzing

```go
func FuzzParseInput(f *testing.F) {
    f.Add("valid-input")
    f.Add("")

    f.Fuzz(func(t *testing.T, input string) {
        result, err := ParseInput(input)
        if err == nil && result == nil {
            t.Error("non-nil result expected when no error")
        }
    })
}
```

**When to add fuzzing:** parsers, decoders, input validation, any function that processes untrusted external data.

## Coverage & Scope

- **DO NOT** write tests solely to increase coverage percentage
- **ONLY** test meaningful scenarios that verify actual behavior
- Focus on business logic, edge cases, and error handling

**DO NOT Test:**
- Standard library behavior (trust Go team)
- Third-party package implementations
- Compiler/runtime guarantees
- External services in unit tests (use mocks or integration tests)
