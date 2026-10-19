# Community Resource Reservation API

[![CI](https://github.com/nishithata/community-reservations-api/actions/workflows/ci.yml/badge.svg)](https://github.com/nishithata/community-reservations-api/actions/workflows/ci.yml)

A Ruby on Rails REST API for booking shared community resources (rooms, equipment, garden plots, vehicles), built for the **Community of Guardians** project. It handles the full reservation lifecycle with JWT authentication, role-based authorization, pagination, and **database-level protection against double bookings**, plus a small browser demo client.

- **Live demo UI:** _add your Vercel URL here_
- **Live API:** _add your Render URL here_ (`/api/v1/health`)
- **Demo login:** `demo@example.com` / `demo-password-123`

> The demo API runs on a free tier that sleeps when idle; the first request can take ~30-60 seconds.

## Highlights

| Area | What it does |
|---|---|
| **REST API** | Versioned JSON API (`/api/v1`) with resource CRUD, reservations, availability, and correct status codes (200, 201, 204, 400, 401, 403, 404, 409, 422, 429) |
| **Data integrity** | ActiveRecord validations backed by PostgreSQL check constraints, unique indexes, foreign keys, and a **GiST exclusion constraint** that makes overlapping bookings impossible, even under concurrent requests |
| **Auth** | JWT bearer tokens (`has_secure_password` + bcrypt); roles are always read from the database, never trusted from the token |
| **Authorization** | Plain-Ruby policy objects: admins manage resources; members see and cancel only their own reservations (others return 404, not 403) |
| **Pagination & filtering** | Pagy offset pagination (`page`, `per_page` capped at 100) with `meta` totals; filter by category, search term, status, resource, and time window |
| **Errors** | One consistent JSON error shape with machine-readable codes and field-level details |
| **Hardening** | Rate limiting on login, sign-up, and booking; CORS allow-list; filtered logs; HTTPS enforced in production; no secrets in the repo |
| **Testing** | 87 Minitest model and request tests, plus end-to-end smoke and concurrency race scripts run against a live server |
| **Delivery** | GitHub Actions (security scan, lint, tests, production-mode end-to-end), Dockerfile + Docker Compose, Render Blueprint, Vercel-ready demo UI |

## Tech stack

Ruby 3.4 · Rails 8.1 (API mode) · PostgreSQL · ActiveRecord · JWT · bcrypt · Pagy · rack-cors · Minitest · RuboCop · Brakeman · GitHub Actions · Docker · Render · Vercel (vanilla JS demo client)

## Quick start

Requirements: Ruby 3.4, PostgreSQL 14+.

```bash
git clone https://github.com/nishithata/community-reservations-api.git
cd community-reservations-api
bin/setup --skip-server      # installs gems, creates and migrates the database
bin/rails db:seed            # demo users, resources, and reservations
bin/rails server             # http://localhost:3000
```

Open the demo UI in a second terminal:

```bash
cd web && python3 -m http.server 8091   # http://localhost:8091 (talks to localhost:3000)
```

Or run everything in Docker:

```bash
docker compose up --build
docker compose exec api bin/rails db:seed
```

## Try the API

```bash
# Log in as the demo member
TOKEN=$(curl -s -X POST http://localhost:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@example.com","password":"demo-password-123"}' | ruby -rjson -e 'puts JSON.parse($stdin.read)["token"]')

# Browse rooms and pick the first one
curl -s "http://localhost:3000/api/v1/resources?category=room&per_page=5"
RESOURCE_ID=$(curl -s "http://localhost:3000/api/v1/resources?category=room" | ruby -rjson -e 'puts JSON.parse($stdin.read)["data"][0]["id"]')

# Book a slot
curl -s -X POST http://localhost:3000/api/v1/reservations \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "{\"reservation\":{\"resource_id\":$RESOURCE_ID,\"starts_at\":\"2030-01-15T10:00:00Z\",\"ends_at\":\"2030-01-15T11:00:00Z\"}}"
```

Booking the same slot again returns `409 reservation_conflict`. See **[docs/API.md](docs/API.md)** for every endpoint with request and response examples.

## Endpoints

| Method | Path | Auth | Description |
|---|---|---|---|
| `GET` | `/up` | none | Liveness probe |
| `GET` | `/api/v1/health` | none | Health check including the database |
| `POST` | `/api/v1/auth/register` | none | Create a member account, returns a token |
| `POST` | `/api/v1/auth/login` | none | Exchange email and password for a token |
| `GET` | `/api/v1/me` | user | Current user |
| `GET` | `/api/v1/resources` | optional | List resources (paginated, filterable) |
| `GET` | `/api/v1/resources/:id` | optional | Show a resource |
| `GET` | `/api/v1/resources/:id/availability?date=YYYY-MM-DD` | optional | Booked slots for a UTC day |
| `POST` | `/api/v1/resources` | admin | Create a resource |
| `PATCH` | `/api/v1/resources/:id` | admin | Update or deactivate a resource |
| `DELETE` | `/api/v1/resources/:id` | admin | Delete a resource with no reservations |
| `GET` | `/api/v1/reservations` | user | List reservations (own, or all for admins) |
| `GET` | `/api/v1/reservations/:id` | user | Show a reservation |
| `POST` | `/api/v1/reservations` | user | Create a reservation |
| `PATCH` | `/api/v1/reservations/:id/cancel` | user | Cancel a reservation |

## Testing

```bash
bin/rails test                                     # 87 model and request tests
bin/rubocop && bin/brakeman                        # style and security scan
ruby script/smoke_test.rb http://localhost:3000    # end-to-end against a running server
ruby script/race_test.rb http://localhost:3000 10  # 10 simultaneous bookings, exactly 1 wins
```

The suite covers resource CRUD, reservation creation and cancellation, filtering, pagination, validation errors, authentication failures (missing, malformed, expired, forged tokens), authorization boundaries, and the database constraints on their own (by bypassing model validation).

## Project layout

```
app/
  controllers/api/v1/   auth, resources, reservations, health
  controllers/concerns/ authentication, authorization, error_handling, pagination
  models/               user, resource, reservation
  policies/             resource_policy, reservation_policy
  serializers/          JSON shapes for each model
  services/             json_web_token
db/migrate/             schema with constraints and the exclusion constraint
test/models/            model and database-constraint tests
test/integration/       API request tests
script/                 smoke_test.rb, race_test.rb
web/                    static demo client for Vercel
docs/                   API reference, architecture notes, deployment guide
```

## Documentation

- **[docs/API.md](docs/API.md):** endpoints, parameters, and example requests and responses
- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md):** design decisions and trade-offs
- **[docs/DEPLOYMENT.md](docs/DEPLOYMENT.md):** deploying the API to Render and the UI to Vercel

## License

MIT
