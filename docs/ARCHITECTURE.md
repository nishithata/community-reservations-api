# Architecture and Design Decisions

This document explains how the API is put together and why. Each section ends with the trade-off that was made.

## Overview

```
Browser (web/ on Vercel)
   │  HTTPS + JSON, Authorization: Bearer <JWT>
   ▼
Rails 8.1 API (Render)
   ├── Rack::Cors            allow-listed origins
   ├── Routes                /api/v1/...
   ├── Controllers           thin: parse params, authorize, call the model, render
   │     └── Concerns        Authentication · Authorization · ErrorHandling · Pagination
   ├── Policies              who may do what (plain Ruby)
   ├── Models                validations, scopes, state transitions
   └── Serializers           explicit JSON shapes
   ▼
PostgreSQL                   constraints are the final source of truth
```

The app follows Rails MVC. In API mode, the "view" layer is the serializers.

## Data model

```
users ──< reservations >── resources
```

| Table | Key columns | Database rules |
|---|---|---|
| `users` | `email`, `password_digest`, `role` | unique `email`; `role IN ('member','admin')` |
| `resources` | `name`, `category`, `capacity`, `active` | unique `name`; allowed categories; `capacity > 0` |
| `reservations` | `user_id`, `resource_id`, `starts_at`, `ends_at`, `status`, `cancelled_at` | foreign keys; `ends_at > starts_at`; allowed statuses; **no overlapping confirmed bookings** |

Indexes match the real query patterns: `(resource_id, starts_at)` for availability and conflict checks, `(user_id, starts_at)` for "my reservations", and `(active, category)` for the catalog.

**Trade-off:** rules are written twice (model validation and database constraint). The model gives friendly, field-level messages; the database guarantees correctness even when code is bypassed or requests race.

## Preventing double bookings

This is the core correctness problem. A plain "check, then insert" has a race:

```
Request A: SELECT overlapping? -> none
Request B: SELECT overlapping? -> none
Request A: INSERT  ✓
Request B: INSERT  ✓   ← double booking
```

The fix is a PostgreSQL **exclusion constraint** (using the `btree_gist` extension):

```sql
EXCLUDE USING gist (
  resource_id WITH =,
  tsrange(starts_at, ends_at, '[)') WITH &&
) WHERE (status = 'confirmed')
```

In plain terms: for the same resource, no two confirmed time ranges may overlap.

- `'[)'` makes ranges half-open, so 10:00-11:00 and 11:00-12:00 don't conflict.
- `WHERE status = 'confirmed'` lets a cancelled booking free its slot without deleting history.
- The constraint is enforced inside the database, atomically, so it holds under any level of concurrency.

The request flow:

1. `Reservation#no_overlapping_reservation` catches the common case and returns `409` with a clear message.
2. If two requests pass that check at the same moment, the second `INSERT` violates the constraint. Rails raises `ActiveRecord::ExclusionViolation`, which `ErrorHandling` maps to the same `409 reservation_conflict`.

This is proven three ways:

- `test/models/reservation_test.rb` saves with `validate: false` and asserts the database raises.
- `test/integration/api/v1/reservations_test.rb` disables the model check and asserts the API still returns `409`.
- `script/race_test.rb` fires many simultaneous HTTP requests at a live server and asserts exactly one wins. CI runs it on every push.

**Alternatives considered:**

- *Row lock on the resource (`SELECT ... FOR UPDATE`).* This works, but it serializes every booking for a resource and only protects code paths that remember to take the lock.
- *Application-level mutex or Redis lock.* This adds infrastructure and doesn't survive multiple app servers or direct database writes.

## Authentication

- Passwords use `has_secure_password` (bcrypt). Emails are normalized to lowercase before validation and lookup.
- Login returns a signed JWT (`HS256`, 24-hour expiry) containing `sub` (user ID) and `exp`.
- `Authentication#authenticate!` verifies the signature and expiry, then **loads the user from the database**. The `role` claim in the token is never trusted, so demoting an admin takes effect on their next request.
- Failed logins return one generic message so attackers can't tell whether an email exists.
- The signing secret comes from `JWT_SECRET` (falling back to `secret_key_base`) and is never committed.

**Trade-off:** stateless JWTs can't be revoked individually before they expire. For this scope a short expiry is enough; a production system might add refresh tokens or a token denylist.

## Authorization

Plain-Ruby policies (`app/policies`) answer "may this user do this action on this record?":

```ruby
authorize!(@reservation, :cancel?)   # -> ReservationPolicy#cancel? or 403
```

Policies also provide query scopes, `ReservationPolicy.scope(user)` and `ResourcePolicy.scope(user)`, and controllers look records up through them. That means a member asking for someone else's reservation gets **404, not 403**, so the API doesn't reveal which IDs exist.

**Trade-off:** a gem like Pundit offers the same pattern with more features. Small explicit classes keep the rules easy to read and test without extra dependencies.

## Error handling

`ErrorHandling` turns exceptions into one JSON shape: `{ error: { code, message, details? } }`. Controllers just call `save!` and `update!`, and the concern chooses the status:

| Exception | Status |
|---|---|
| `RecordNotFound` | 404 |
| `ParameterMissing`, bad filter, bad JSON | 400 |
| `RecordInvalid` | 422, or 409 when the error is an overlap |
| `ExclusionViolation` | 409 |
| `RecordNotDestroyed` | 409 |
| `AuthenticationError` / `ForbiddenError` | 401 / 403 |
| anything else | 500 with a request ID (stack traces are logged, never returned) |

## Pagination and filtering

Pagy offset pagination (`page`, `per_page` capped at 100) with a `meta` block that includes totals, so clients can render page controls. Filters are allow-listed: an unknown `category` or `status` returns `400` instead of silently returning nothing. Search uses `ILIKE` with `sanitize_sql_like`, so `%` and `_` in user input are treated literally.

**Trade-off:** offset pagination is simple and supports "page X of Y". For very large tables, keyset (cursor) pagination avoids slow deep offsets; Pagy supports both.

## Hardening

- **Rate limiting** (Rails 8 `rate_limit`): login (10/min per IP), sign-up (5 per 10 min per IP), and booking (30/min per user).
- **CORS:** only origins listed in `CORS_ORIGINS` may call the API from a browser. Credentials (cookies) are never allowed cross-origin.
- **Strong parameters:** clients can't set `role`, `user_id`, `status`, or `cancelled_at`.
- **Log filtering:** passwords, tokens, emails, and authorization headers are filtered from logs.
- **HTTPS:** enforced in production (`force_ssl` with `assume_ssl` behind Render's proxy). `/up` is exempt so health checks work.
- **No secrets in the repo:** no `master.key` or credentials file; production secrets come from environment variables.
- **Static analysis:** Brakeman and bundler-audit run in CI.

## Testing strategy

| Layer | Where | What it proves |
|---|---|---|
| Model | `test/models` | Validations, normalization, scopes, state transitions, and that the database constraints hold on their own |
| Request | `test/integration/api/v1` | Every endpoint's status codes, JSON shape, auth failures, authorization boundaries, pagination, filters |
| End to end | `script/smoke_test.rb` | The real HTTP stack against a running server (local or deployed) |
| Concurrency | `script/race_test.rb` | Simultaneous bookings for one slot produce exactly one success |

CI runs the security scan, lint, the test suite, and then boots the app **in production mode** to run the end-to-end and race scripts.

## What I would add next

- Refresh tokens and logout or revocation
- Recurring reservations and per-resource booking windows (e.g. opening hours)
- An OpenAPI specification generated from request tests
- Background email notifications (Active Job) for confirmations and reminders
- Keyset pagination and caching for large catalogs
