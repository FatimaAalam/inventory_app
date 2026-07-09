#!/bin/bash
#
# healthcheck.sh
# Verifies that all services in the inventory stack are up and responding.
# Exits 0 if everything is healthy, exits 1 (with details) if anything failed.

set -e

FAILED=0

echo "Checking PostgreSQL..."
if docker compose exec -T postgres pg_isready -U "$POSTGRES_USER" > /dev/null 2>&1; then
    echo "  OK - PostgreSQL is ready"
else
    echo "  FAIL - PostgreSQL is not ready"
    FAILED=1
fi

echo "Checking MongoDB..."
if docker compose exec -T mongo mongosh --quiet --eval "db.adminCommand('ping')" > /dev/null 2>&1; then
    echo "  OK - MongoDB is ready"
else
    echo "  FAIL - MongoDB is not ready"
    FAILED=1
fi

echo "Checking Redis..."
if docker compose exec -T redis redis-cli ping | grep -q "PONG"; then
    echo "  OK - Redis is ready"
else
    echo "  FAIL - Redis is not ready"
    FAILED=1
fi

echo "Checking App (via Nginx)..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/health)
if [ "$HTTP_STATUS" -eq 200 ]; then
    echo "  OK - App is healthy (HTTP $HTTP_STATUS)"
else
    echo "  FAIL - App health check returned HTTP $HTTP_STATUS"
    FAILED=1
fi

echo "Checking Nginx..."
NGINX_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/)
if [ "$NGINX_STATUS" -lt 500 ]; then
    echo "  OK - Nginx is responding (HTTP $NGINX_STATUS)"
else
    echo "  FAIL - Nginx returned HTTP $NGINX_STATUS"
    FAILED=1
fi

if [ "$FAILED" -eq 1 ]; then
    echo ""
    echo "One or more services failed health checks."
    exit 1
else
    echo ""
    echo "All services are healthy."
    exit 0
fi