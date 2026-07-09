#------------------Stage 1: Builder ------------------#
FROM python:3.11-slim AS builder

#Install build dependencies needed to compile psycopg2

RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install Python packages into a specific location
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

#------------------Stage 2: Final Image ------------------#
FROM python:3.11-slim


# Install only the runtime library (not the -dev/compiler version)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy the installed packages from the builder stage
COPY --from=builder /install /usr/local

# Copy the application code
COPY app/ .

# Run as a non-root user for security
RUN useradd --create-home appuser
USER appuser

EXPOSE 5000

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "app:app"]

