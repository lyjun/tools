# REST API — Security, Reliability, Advanced

Load together with `rest-api.md` when the endpoint involves authentication, cross-origin access, retry safety, rate limiting, caching, or batch operations. `rest-api.md` covers resource modeling, status codes, envelopes, and pagination.

## Authentication & Authorization

| Method | Use |
|--------|-----|
| Bearer token (JWT) | Normal user authentication |
| OAuth 2.0 | Third-party authorization |
| API key | Server-to-server, external integration |

- Tokens go in the `Authorization` header, never in the query string — query strings land in access logs and referrer headers
- Distinguish `401` (not authenticated) from `403` (authenticated, lacks permission)
- Pair API keys with scopes so a leaked key has bounded blast radius

```
Authorization: Bearer eyJhbGciOiJIUzI1NiIs...
```

## CORS

```
Access-Control-Allow-Origin: https://app.example.com
Access-Control-Allow-Methods: GET, POST, PUT, PATCH, DELETE, OPTIONS
Access-Control-Allow-Headers: Content-Type, Authorization
Access-Control-Max-Age: 86400
```

- Never `Access-Control-Allow-Origin: *` in production
- Handle the preflight `OPTIONS` request explicitly
- `*` is incompatible with `Access-Control-Allow-Credentials: true` — the browser rejects the response, so a credentialed endpoint must echo a specific origin
- Set `Access-Control-Max-Age` so browsers stop re-issuing preflights

## Security Baseline

| Item | Rule |
|------|------|
| HTTPS | Required everywhere; no plaintext HTTP |
| Input validation | Validate every external input at the boundary (SQL injection, command injection) |
| Secrets | Passwords and tokens never appear in a URL — access logs capture them |
| Response headers | Set `X-Content-Type-Options: nosniff` and `Strict-Transport-Security` |
| Error bodies | No stack traces or internal implementation detail in production responses |
| Log redaction | Mask passwords, card numbers, and personal data in logs |

## Idempotency

| Method | Idempotent | Note |
|--------|-----------|------|
| `GET` | Yes | Read does not change state |
| `PUT` | Yes | Full overwrite; repeat gives the same result |
| `DELETE` | Yes | Deleting an already-deleted resource must not error |
| `PATCH` | Depends | Determined by the patch semantics |
| `POST` | No | Each call may create a new resource |

### Idempotency-Key

A client can attach `Idempotency-Key` to a non-idempotent request so a retry does not create a second record:

```
POST /orders
Idempotency-Key: unique-request-id-12345
```

The server replays the stored result for a repeat of the same key within a defined window.

Two things this requires before it is real: the dedup window length, and where the previous response is stored. Without both, the header is decorative.

Standards status: `Idempotency-Key` is `draft-ietf-httpapi-idempotency-key-header` (Standards Track, still a draft — not an RFC). No ardge service accepts this header today (other flows have their own idempotency rules, but none keyed on `Idempotency-Key`), so an endpoint that needs it is defining the behavior, not adopting an existing one.

## Rate Limiting

What the platform APIs actually do today: return `429` (or `503`) and set `Retry-After` in seconds — `setRetryAfter` in `arx-platform-api/internal/handler/httputil/response.go:112` converts an error detail's retry timestamp into that header. No handler emits a quota header of any kind; the only rate-limit fields in the codebase are ones we *read* from Docker Hub (`ratelimit-limit`, `ratelimit-remaining` parsed in `arx-platform-manager/internal/dockerhub/ratelimit.go:24`).

If an endpoint needs to advertise quota, prefer the standardized fields over the legacy triple:

```
RateLimit: "default";r=99;t=60
RateLimit-Policy: "default";q=100;w=60
```

- `RateLimit` / `RateLimit-Policy` are defined by `draft-ietf-httpapi-ratelimit-headers` (Standards Track, draft — not yet an RFC)
- `X-RateLimit-Limit` / `X-RateLimit-Remaining` / `X-RateLimit-Reset` appear in that draft's Appendix D as the widely deployed de-facto convention, not as standard fields; RFC 6648 also deprecates new `X-` prefixed field names
- When a response carries both `Retry-After` and `RateLimit`, the draft says `Retry-After` takes precedence for the client

The 429 body uses the standard error envelope:

```json
{
  "apiVersion": "1.0",
  "error": {
    "code": 429,
    "message": "Too many requests, please retry after 60 seconds",
    "errors": [
      {
        "domain": "rateLimit",
        "reason": "RateLimitExceeded",
        "message": "Too many requests, please retry after 60 seconds"
      }
    ]
  }
}
```

## Caching

| Header | Purpose |
|--------|---------|
| `Cache-Control` | Caching policy (`max-age`, `no-cache`, `private`, `no-store` for sensitive responses) |
| `ETag` | Version identifier for the representation |
| `Last-Modified` | Last modification time |
| `If-None-Match` | Client sends back the ETag to ask whether it changed |
| `If-Modified-Since` | Client sends back a timestamp to ask whether it changed |

Flow: the server returns `ETag` or `Last-Modified`; the client replays it as `If-None-Match` or `If-Modified-Since`; unchanged resources answer `304 Not Modified` with no body.

Worked example in the codebase: the avatar endpoint in `ardge-cloud-service/internal/account-center/user/handler.go` (`getAvatar`, with the hash in `avatarETag`) sets a strong `ETag` derived from the image bytes, sends `Cache-Control`, and answers `304` when `If-None-Match` matches.

The precondition is a hash over stable bytes. Hashing a freshly serialized struct whose field or map order can shift produces a new ETag for unchanged data, which is worse than sending none.

## Batch Operations

Provide a batch endpoint when a client would otherwise issue N calls:

```
POST /users/batch
{ "items": [ { "name": "Alice" }, { "name": "Bob" } ] }

DELETE /users/batch
{ "ids": [1, 2, 3] }
```

Report per-item outcomes so the client learns which entries failed:

```json
{
  "apiVersion": "1.0",
  "data": {
    "items": [
      { "id": 1, "status": "success", "error": null },
      { "id": 2, "status": "error", "error": { "code": "NOT_FOUND", "message": "User not found" } }
    ]
  }
}
```

Decide and document which of the two the endpoint is: all-or-nothing (one failure rolls the batch back) or per-item (partial success returns `200` with failures inside `items`). A per-item batch that returns a bare `200` with no per-item status is unusable — the caller cannot tell what happened.

## HATEOAS

Optional. Include related-resource links when the API graph is complex enough that clients benefit from discovering transitions:

```json
{
  "apiVersion": "1.0",
  "data": {
    "id": 1,
    "name": "Alice",
    "links": {
      "self": "/api/v1/users/1",
      "orders": "/api/v1/users/1/orders",
      "deactivate": "/api/v1/users/1/deactivate"
    }
  }
}
```

Simple APIs do not need it.

## API Documentation

- Write the spec in OpenAPI, serve an interactive view (Swagger UI or Redoc), and give every endpoint a request/response example
- Cover: authentication, every request/response schema, the error-code table, rate limits, and a changelog

In repos where the spec is generated from handler doc comments (`swag init`, output under `docs/swagger/`), changing a comment means regenerating and committing the spec in the same change — the generated file is part of the API surface, not a build artifact.
