# REST API Design Rules

Load when designing or modifying HTTP handlers / RESTful endpoints.

## Resource Modeling

### Resource Types

| Type | Convention | Example |
|------|-----------|---------|
| Collection | Plural noun | `GET /users` |
| Resource | ID-identified single item | `GET /users/{id}` |
| Sub-collection | Plural under parent | `GET /users/{id}/orders` |
| Singleton | Single child of parent, no ID | `GET /users/{id}/profile` |
| Controller (action) | Verb — the only place a verb is allowed in URL | `POST /orders/{id}/cancel` |

### Naming

- **Nouns, plural**: `/users`, `/orders`, `/products`. Never `/getUser` or `/createOrder` — use HTTP method for the verb
- **Multi-word resources → kebab-case**: `/model-instances`, `/api-keys`, `/access-rules` (never `modelInstances` or `model_instances`)
- **Nesting ≤ 2 levels**: `/users/{id}/orders/{oid}` OK; `/users/{id}/orders/{oid}/items/{iid}` is too deep — flatten to `/order-items/{iid}`

### CRUD vs Non-CRUD

For actions that don't map to CRUD, the decision rule is:

> **Will callers need to `GET` this action's result later?**
>
> - **Yes** → action produces a record → model as **resource (noun)**
> - **No** → fire-and-forget → model as **controller (verb)**

Controller (verb) — one-shot, no record:

```
POST /orders/{id}/cancel
POST /users/{id}/reset-password
POST /users/{id}/send-otp
```

Resource (noun) — produces a record with lifecycle:

```
POST /payments/{id}/refunds       # refund record
POST /reports/exports             # async job, queryable
POST /teams/{id}/invitations      # has pending/accepted/expired states
POST /services/{id}/deployments   # has history, rollbackable
```

## HTTP Status Codes

Never use `200 OK` + error body. Pick the correct status code.

### 2xx — Success

| Code | Use |
|------|-----|
| `200 OK` | Successful read / update |
| `201 Created` | Sync create succeeded. **SHOULD** include `Location` header pointing to the new resource |
| `202 Accepted` | Async work accepted. **MAY** include `Location` header pointing to a status endpoint |
| `204 No Content` | Success with no body (common for sync delete or non-returning update) |

Example:

```http
HTTP/1.1 201 Created
Location: /api/v1/users/123
```

### 4xx — Client Error

| Code | Use |
|------|-----|
| `400` | Malformed request, invalid parameters |
| `401` | Unauthenticated (missing / invalid token) |
| `403` | Authenticated but lacks permission |
| `404` | Resource does not exist |
| `405` | Method not allowed on this resource |
| `409` | State conflict (e.g., duplicate create) |
| `410` | Resource permanently removed |
| `413` | Payload exceeds server limit |
| `415` | Unsupported Content-Type |
| `422` | Syntactically valid but semantically invalid (validation failure) |
| `429` | Rate limited — pair it with a `Retry-After` header; see `rest-api-advanced.md` |

### 5xx — Server Error

| Code | Use |
|------|-----|
| `500` | Internal error |
| `502` | Upstream unreachable |
| `503` | Temporarily unavailable (maintenance / overload) |
| `504` | Upstream timed out |

### 3xx — Redirect

- `301` / `308` are **cached** by clients — do not use unless permanent migration
- Use `302` / `307` for temporary redirects (`307` preserves the HTTP method)

## Request / Response Format

### Universal Rules

- JSON only, `Content-Type: application/json`
- **Field naming**: `camelCase` everywhere — request body, response body, query parameters that reference fields (e.g., `orderBy`, `filter`)
- **Time fields**: RFC 3339 string, UTC ends with `Z` (e.g., `2026-05-07T10:30:00Z`)
- **Envelope** (mandatory): top level has `apiVersion` + exactly one of `data` or `error`. Never invent custom envelopes like `{success, result}` or `{ok, payload}`

### Success Envelope

Single resource:

```json
{
  "apiVersion": "1.0",
  "data": {
    "id": 1,
    "name": "Alice",
    "email": "alice@example.com"
  }
}
```

List response — pagination fields flattened into `data`, not nested under `meta`:

```json
{
  "apiVersion": "1.0",
  "data": {
    "items": [
      { "id": 1, "name": "Alice" },
      { "id": 2, "name": "Bob" }
    ],
    "totalSize": 100,
    "pageSize": 10,
    "currentPage": 1,
    "totalPages": 10,
    "hasNext": true,
    "hasPrevious": false
  }
}
```

### Error Envelope

```json
{
  "apiVersion": "1.0",
  "error": {
    "code": 400,
    "message": "invalid query parameters",
    "errors": [
      {
        "domain": "validation",
        "reason": "InvalidInput",
        "message": "email is required",
        "location": "email",
        "locationType": "field"
      }
    ]
  }
}
```

- `code` mirrors the HTTP status code
- `message` is human-readable
- `errors[]` is optional, for per-field validation detail

### Response Field Rules

(From `x-coding-standards/SKILL.md` HTTP API section — restated for proximity:)

- **No `omitempty` on response fields**: every documented field appears, with zero values (`""`, `0`, `false`, `[]`) when absent. Clients bind by field name, not by key existence
- **Empty array = `[]`, not `null`**: initialize slices as empty slices to ensure JSON serializes to `[]`

## Numeric Field Design

Numeric fields are often distorted to match UI display rather than backend semantics. **Schema is API-driven, not UI-driven.**

### Unit — raw, not scaled

- Use the raw unit the backend actually processes: tokens, bytes, milliseconds, seconds
- Do not use scaled units (K-tokens, MB, minutes) just because UI displays them that way — UI formatters belong in the frontend
- Scaled units force fractional values (`0.5` K-tokens for a 512-token model), introducing float precision issues

```yaml
# Bad — UI-driven scaling leaks into schema
contentLength: 8        # actually 8 * 1024 tokens; a 512-token model becomes 0.5

# Good — raw unit; UI formats it
contentLength: 8192
```

### Type — prefer integer

- Counts / sizes / tokens / IDs MUST be `integer`
- Switching `integer` → `number` later to support smaller units is a Breaking Change (OpenAPI codegen clients break) and introduces float equality bugs. Reshaping a field that is already published has its own rules — see `contract-change.md`

### Bounds — must trace to a real use case

- `min` / `max` must correspond to a real use case or external metadata, not a hand-picked "safety" number
- Document the source in PR description or schema comment (e.g. `min=512 because MiniLM-L6-v2's max_position_embeddings`)
- Reject magic-number bounds like `min=0.1`, `max=999999`

### Dynamic upper bounds — validate at runtime, not in schema

When the upper bound depends on external metadata (model `max_position_embeddings`, filesystem capacity, available memory), validate in the backend and return a specific error. Do **not** hardcode such bounds in OpenAPI / proto schema — clients otherwise assume schema-valid input will always succeed.

## List Query Parameters

All list endpoints share these parameter names:

| Name | Type | Default | Example |
|------|------|---------|---------|
| `page` | int32 | `1` | `?page=2` |
| `pageSize` | int32 | `10` | `?pageSize=20` |
| `orderBy` | string | per-API | `?orderBy=createdAt desc` |
| `search` | string | empty | `?search=keyword` (case-insensitive substring) |
| `filter` | string | empty | `?filter=status=="active"` (CEL expression) |

- `pageSize=0` or missing → server-side default
- Query parameter names are **case-sensitive** per RFC 3986 — `pageSize` ✓, `pagesize` / `PAGESIZE` are ignored
- `orderBy` supports multi-column: `?orderBy=role asc, createdAt desc`

### Pagination Modes

| Mode | When to Use |
|------|-------------|
| Offset-based (`page` + `pageSize`) | Default — bounded datasets |
| Cursor-based (`cursor` + `limit`) | Large / mutating streams, deep pagination |

Cursor response:

```json
{
  "apiVersion": "1.0",
  "data": {
    "items": [],
    "nextCursor": "def456",
    "hasMore": true
  }
}
```

### Filtering

Use [CEL](https://cel.dev/) for `filter`. CEL is non-Turing-complete and termination-guaranteed — safe for user-supplied predicates.

```
?filter=role=="admin"
?filter=role=="admin" && status=="active"
?filter=createdAt>"2025-01-01"
?filter=email.contains("@example.com")
```

`&&` in CEL is a query-string trap: unencoded `&` is a parameter separator. Tell users to quote the URL when using `curl`, or URL-encode `&&` as `%26%26`.

## Versioning

URL-path versioning, applied consistently across the whole API:

| Path | Meaning |
|------|---------|
| `/api/v1/users` | Pinned to v1 |
| `/api/v2/users` | Pinned to v2 |
| `/api/users` | Latest (alias) — clients should read `apiVersion` from response |

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| `GET /getUsers`, `POST /createUser` | Use noun + HTTP method: `GET /users`, `POST /users` |
| `/userOrders`, `/api_keys` | kebab-case for multi-word: `/user-orders`, `/api-keys` |
| `/users/{id}/orders/{oid}/items/{iid}` | Flatten: `/order-items/{iid}` |
| `{success: true, result: ...}` | Use `apiVersion` + `data` envelope |
| `"createdAt": 1716489600` (epoch) | Use RFC 3339: `"createdAt": "2025-05-07T10:30:00Z"` |
| Returning `200 OK` with `{error: ...}` | Use the appropriate 4xx / 5xx status code |
| `omitempty` on response fields | Always emit documented fields with zero values |
| List response: `{data: [...], meta: {page, total}}` | Flatten pagination into `data`: `{items, totalSize, ...}` |
| `pagesize=20` in query | Parameter names are case-sensitive — must be `pageSize` |
