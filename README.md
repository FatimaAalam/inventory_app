# Inventory Management REST API

A production-style containerised REST API for managing inventory items, built as a final project tying together a full DevOps stack: Flask, PostgreSQL, MongoDB, Redis, and Nginx. all orchestrated with Docker Compose, with a CI pipeline and Prometheus metrics on top.

## Architecture

```
Client → Nginx (:80) → Flask/Gunicorn (app:5000)
                            ├── PostgreSQL   → items table (persistent volume)
                            ├── MongoDB      → inventory_audit.events (audit log)
                            └── Redis        → cache-aside layer (60s TTL)
```

All services run on a shared Docker bridge network (`inventory_net`). Nginx is the only container that exposes a port to the host; every other service is reachable only from within the network.

## Tech Stack

| Component | Technology |
|---|---|
| API | Python 3.11, Flask, Gunicorn |
| Primary database | PostgreSQL 15 |
| Secondary datastore | MongoDB 6 (audit/event log) |
| Cache | Redis 7 |
| Reverse proxy | Nginx (stable) |
| Metrics | Prometheus (via `prometheus-flask-exporter`) |
| CI/CD | GitHub Actions |

## Project Structure

```
inventory_app/
├── Dockerfile                      # Multi-stage build for the Flask app
├── docker-compose.yml              # All 5 services + volumes + network
├── healthcheck.sh                  # Standalone service health check script
├── nginx/
│   └── nginx.conf                  # Reverse proxy config
├── app/
│   ├── app.py                      # Flask application and routes
│   ├── db.py                       # DB connection helpers (Postgres/Mongo/Redis)
│   ├── requirements.txt            # Python dependencies
│   └── --init--.sql                # Postgres schema, auto-run on first boot
└── .github/
    └── workflows/
        └── docker-build.yml        # CI: builds and pushes image on every push to main
```

## API Endpoints

| Method | Path | Description |
|---|---|---|
| `POST` | `/items` | Creates a new item in PostgreSQL and logs a "item created" audit event to MongoDB |
| `GET` | `/item/<id>` | Fetches an item by ID. Checks Redis first (cache-aside); falls back to PostgreSQL on a miss and repopulates the cache with a 60s TTL |
| `GET` | `/health` | Reports connectivity status for the app, PostgreSQL, MongoDB, and Redis. Returns `200` if all are reachable, `503` otherwise. Used by `healthcheck.sh` and Docker Compose health checks |
| `GET` | `/metrics` | Exposes Prometheus-format metrics: Python runtime stats (GC, memory, CPU) plus Flask request counters and latency histograms per route/method/status |

### Example requests

**Create an item:**
```bash
curl -X POST http://localhost/items \
  -H "Content-Type: application/json" \
  -d '{"name": "Widget", "quantity": 10, "price": 9.99}'
```
Response:
```json
{"id": 1, "name": "Widget", "price": 9.99, "quantity": 10}
```

**Fetch an item (cache-aside):**
```bash
curl http://localhost/item/1
```
First call → `"source": "database"`. Repeat within 60 seconds → `"source": "cache"`.

**Health check:**
```bash
curl http://localhost/health
```
```json
{"app": "ok", "mongo": "ok", "postgres": "ok", "redis": "ok"}
```

**Metrics:**
```bash
curl http://localhost/metrics
```

## Database Schema

`items` table (PostgreSQL), created automatically on first container start via `app/--init--.sql`:

```sql
CREATE TABLE IF NOT EXISTS items (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    quantity INTEGER NOT NULL,
    price NUMERIC(10, 2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

MongoDB collection `inventory_audit.events` is created implicitly on first write. no schema migration needed, documents are inserted as `{event, item_id, name, timestamp}`.

## Setup and Deployment

### Prerequisites
- Docker and Docker Compose installed
- Port 80 free on the host (or adjust the Nginx port mapping in `docker-compose.yml`)

### 1. Clone the repository
```bash
git clone https://github.com/FatimaAalam/inventory_app.git
cd inventory_app
```

### 2. Configure environment variables
Create a `.env` file in the project root (this is git-ignored and never committed):
```env
POSTGRES_USER=your_postgres_user
POSTGRES_PASSWORD=your_postgres_password
POSTGRES_DB=inventory_db

MONGO_USER=your_mongo_user
MONGO_PASSWORD=your_mongo_password
```

### 3. Build and start the stack
```bash
docker compose up --build
```
This builds the app image, starts all 5 containers, waits for PostgreSQL to report healthy before starting the app, and runs the Postgres init script automatically on first boot.

### 4. Verify everything is running
```bash
docker ps
curl http://localhost/health
```
Or run the included health check script:
```bash
chmod +x healthcheck.sh
./healthcheck.sh
```

### 5. Access the API
The app is reachable through Nginx on port 80:
```
http://<host>/items
http://<host>/item/<id>
http://<host>/health
http://<host>/metrics
```

### Stopping the stack
```bash
docker compose down
```
Add `-v` to also remove the persistent PostgreSQL/MongoDB volumes:
```bash
docker compose down -v
```

## CI/CD Pipeline

On every push to `main`, `.github/workflows/docker-build.yml` automatically:
1. Checks out the repository
2. Logs into Docker Hub using repository secrets (`DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`)
3. Builds the Docker image from the multi-stage `Dockerfile`
4. Pushes the image to Docker Hub as `<dockerhub-username>/inventory-app:latest`

Pipeline runs are visible under the repository's **Actions** tab.

## Monitoring

The app exposes Prometheus-compatible metrics at `/metrics`, including:
- `flask_http_request_total` — request counts by method, route, and status code
- `flask_http_request_duration_seconds` — request latency histograms
- Python runtime metrics — garbage collection, memory usage, CPU time

These can be scraped by a Prometheus server pointed at `http://<host>/metrics` and visualised in Grafana.

## Notes

- The app container exposes port `5000` internally only. all external traffic must go through Nginx.
- PostgreSQL data persists across restarts via the `postgres_data` named volume; MongoDB data persists via `mongo_data`.
- The Redis cache uses a 60-second TTL per item; expired entries fall back to a PostgreSQL read and are repopulated automatically.
