# API Reference

Base URL: `http://localhost:3000` locally, or your Render URL in production. All endpoints live under `/api/v1`, accept and return JSON, and use UTC ISO 8601 timestamps (`2030-01-15T10:00:00Z`).

The examples below are real responses captured from the running API.

- [Authentication](#authentication)
- [Errors](#errors)
- [Pagination](#pagination)
- [Health](#health)
- [Auth endpoints](#auth-endpoints)
- [Resources](#resources)
- [Reservations](#reservations)

## Authentication

Log in (or register) to get a token, then send it on every request that needs a user:

```
Authorization: Bearer <token>
```

Tokens are signed JWTs (HS256) that expire after 24 hours. The user's role is looked up from the database on every request, so role changes take effect immediately.

| Role | Can do |
|---|---|
| anonymous | Browse active resources and their availability |
| `member` | Everything above, plus create, view, and cancel **their own** reservations |
| `admin` | Everything, including managing resources and viewing or cancelling any reservation |

## Errors

Every error uses the same shape. `code` is stable and machine-readable; `details` appears for validation errors and maps each field to full messages.

```json
{
  "error": {
    "code": "validation_failed",
    "message": "Validation failed",
    "details": {
      "ends_at": ["Ends at must be after starts_at"]
    }
  }
}
```

| Status | `code` | When |
|---|---|---|
| 400 | `bad_request` | Missing payload, or an invalid filter or date value |
| 400 | `invalid_json` | Request body is not valid JSON |
| 401 | `unauthorized` | Missing, malformed, expired, or forged token; wrong credentials |
| 403 | `forbidden` | Authenticated but not allowed (e.g. a member creating a resource) |
| 404 | `not_found` | Unknown record or route, or a record you are not allowed to see |
| 409 | `reservation_conflict` | The slot overlaps an existing confirmed reservation |
| 409 | `conflict` | Deleting a resource that has reservations, or a duplicate record |
| 422 | `validation_failed` | Field validation errors (see `details`) |
| 422 | `invalid_state` | Cancelling a reservation that is already cancelled or has ended |
| 429 | `rate_limited` | Too many login, sign-up, or booking attempts (`Retry-After` header set) |
| 500 | `internal_error` | Unexpected error; the message includes a request ID for the logs |

## Pagination

List endpoints accept `page` (default 1) and `per_page` (default 20, max 100) and return a `meta` block:

```json
"meta": {
  "page": 1,
  "per_page": 2,
  "total_count": 2,
  "total_pages": 1,
  "next_page": null,
  "prev_page": null
}
```

## Health

### `GET /up`

Liveness probe used by the load balancer. Returns `200` if the app booted.

### `GET /api/v1/health`

Also checks the database. Returns `503` with `"database": "unavailable"` if it can't connect.

```json
{ "status": "ok", "database": "ok", "time": "2026-10-19T19:29:24Z" }
```

## Auth endpoints

### `POST /api/v1/auth/register`

Creates a **member** account (a `role` in the body is ignored) and returns a token.

```bash
curl -X POST http://localhost:3000/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{"name":"Sam Rivera","email":"sam@example.com","password":"a-long-password"}'
```

`201 Created`: same body as login. Validation errors return `422`:

```json
{
  "error": {
    "code": "validation_failed",
    "message": "Validation failed",
    "details": {
      "name": ["Name can't be blank"],
      "email": ["Email is invalid"],
      "password": ["Password is too short (minimum is 8 characters)"]
    }
  }
}
```

### `POST /api/v1/auth/login`

```bash
curl -X POST http://localhost:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@example.com","password":"demo-password-123"}'
```

`200 OK`

```json
{
  "token": "eyJhbGciOiJIUzI1NiJ9...",
  "token_type": "Bearer",
  "expires_in": 86400,
  "user": {
    "id": 2,
    "name": "Demo Member",
    "email": "demo@example.com",
    "role": "member",
    "created_at": "2026-10-19T19:21:05Z"
  }
}
```

Wrong credentials return `401` with `"Invalid email or password"`, without revealing which part was wrong. Limited to 10 attempts per minute per IP.

### `GET /api/v1/me`

Returns `{ "data": <user> }` for the token's user.

## Resources

A resource is something people can book. Fields: `name` (unique), `category` (`room`, `equipment`, `space`, `vehicle`), `description`, `location`, `capacity` (positive integer or null), `active`.

### `GET /api/v1/resources`

Public. Inactive resources are only listed for admins.

| Parameter | Description |
|---|---|
| `category` | One of `room`, `equipment`, `space`, `vehicle` (anything else returns `400`) |
| `q` | Case-insensitive search across name and description |
| `active` | `true` or `false` (useful for admins) |
| `page`, `per_page` | Pagination |

```bash
curl "http://localhost:3000/api/v1/resources?category=room&per_page=2"
```

```json
{
  "data": [
    {
      "id": 1,
      "name": "Community Hall",
      "description": "Large hall for meetings, workshops, and celebrations.",
      "category": "room",
      "location": "Main Building, Floor 1",
      "capacity": 80,
      "active": true,
      "created_at": "2026-10-19T19:21:05Z",
      "updated_at": "2026-10-19T19:21:05Z"
    },
    {
      "id": 2,
      "name": "Study Room A",
      "description": "Quiet room with a whiteboard and a TV screen.",
      "category": "room",
      "location": "Library, Floor 2",
      "capacity": 6,
      "active": true,
      "created_at": "2026-10-19T19:21:05Z",
      "updated_at": "2026-10-19T19:21:05Z"
    }
  ],
  "meta": { "page": 1, "per_page": 2, "total_count": 2, "total_pages": 1, "next_page": null, "prev_page": null }
}
```

### `GET /api/v1/resources/:id`

Returns `{ "data": <resource> }`. Inactive resources return `404` unless you are an admin.

### `GET /api/v1/resources/:id/availability?date=YYYY-MM-DD`

Confirmed bookings that overlap the given UTC day. It does not reveal who made them.

```json
{
  "data": {
    "resource_id": 2,
    "date": "2026-10-20",
    "bookings": [
      { "starts_at": "2026-10-20T10:00:00Z", "ends_at": "2026-10-20T12:00:00Z" },
      { "starts_at": "2026-10-20T13:00:00Z", "ends_at": "2026-10-20T15:00:00Z" }
    ]
  }
}
```

A missing or malformed `date` returns `400`.

### `POST /api/v1/resources` (admin)

```bash
curl -X POST http://localhost:3000/api/v1/resources \
  -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" \
  -d '{"resource":{"name":"Pop-up Tent","category":"equipment","capacity":10,"location":"Storage"}}'
```

`201 Created` with a `Location` header. The `resource` wrapper is optional; a flat JSON body works too. Members get `403`, anonymous callers `401`.

### `PATCH /api/v1/resources/:id` (admin)

Partial update. Use `{"resource":{"active":false}}` to retire a resource while keeping its booking history.

### `DELETE /api/v1/resources/:id` (admin)

`204 No Content`. Resources with any reservations can't be deleted (`409 conflict`); deactivate them instead.

## Reservations

Fields: `resource_id`, `starts_at`, `ends_at`, `notes` (optional, max 500 characters), and the read-only `status` (`confirmed` or `cancelled`) and `cancelled_at`.

Booking rules:

- `ends_at` must be after `starts_at`, and the reservation must start in the future
- Length between 15 minutes and 8 hours
- The resource must be active
- No overlap with another **confirmed** reservation for the same resource. Back-to-back is fine (10:00-11:00 and 11:00-12:00), and cancelled reservations don't block the slot

### `GET /api/v1/reservations`

Members see their own reservations; admins see everyone's. Ordered by start time.

| Parameter | Description |
|---|---|
| `status` | `confirmed` or `cancelled` |
| `resource_id` | Only this resource |
| `from` | Reservations ending after this ISO 8601 time |
| `to` | Reservations starting before this ISO 8601 time |
| `page`, `per_page` | Pagination |

```bash
curl "http://localhost:3000/api/v1/reservations?status=confirmed&per_page=2" -H "Authorization: Bearer $TOKEN"
```

```json
{
  "data": [
    {
      "id": 1,
      "status": "confirmed",
      "starts_at": "2026-10-20T10:00:00Z",
      "ends_at": "2026-10-20T12:00:00Z",
      "notes": "Group study session",
      "cancelled_at": null,
      "resource": { "id": 2, "name": "Study Room A" },
      "user": { "id": 2, "name": "Demo Member" },
      "created_at": "2026-10-19T19:21:05Z"
    }
  ],
  "meta": { "page": 1, "per_page": 2, "total_count": 3, "total_pages": 2, "next_page": 2, "prev_page": null }
}
```

### `GET /api/v1/reservations/:id`

Returns `{ "data": <reservation> }`. Another member's reservation returns `404`, so IDs can't be probed.

### `POST /api/v1/reservations`

```bash
curl -X POST http://localhost:3000/api/v1/reservations \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"reservation":{"resource_id":1,"starts_at":"2030-01-15T10:00:00Z","ends_at":"2030-01-15T11:00:00Z","notes":"Book club"}}'
```

`201 Created`

```json
{
  "data": {
    "id": 12,
    "status": "confirmed",
    "starts_at": "2030-01-15T10:00:00Z",
    "ends_at": "2030-01-15T11:00:00Z",
    "notes": "Book club",
    "cancelled_at": null,
    "resource": { "id": 1, "name": "Community Hall" },
    "user": { "id": 2, "name": "Demo Member" },
    "created_at": "2026-10-19T19:29:24Z"
  }
}
```

The reservation always belongs to the token's user; a `user_id` in the body is ignored.

Booking the same slot again returns `409`:

```json
{ "error": { "code": "reservation_conflict", "message": "This time slot overlaps an existing reservation" } }
```

An invalid time range returns `422`:

```json
{
  "error": {
    "code": "validation_failed",
    "message": "Validation failed",
    "details": { "ends_at": ["Ends at must be after starts_at"] }
  }
}
```

Limited to 30 bookings per minute per user.

### `PATCH /api/v1/reservations/:id/cancel`

Owner or admin. Returns the updated reservation with `"status": "cancelled"` and `cancelled_at` set. Cancelling twice, or cancelling a reservation that has already ended, returns `422`:

```json
{ "error": { "code": "invalid_state", "message": "Reservation is already cancelled" } }
```
