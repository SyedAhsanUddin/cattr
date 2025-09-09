#!/usr/bin/env bash
set -e

# --- find the Laravel app automatically ---
ARTISAN_FILE="$(find / -type f -name artisan 2>/dev/null | head -n1)"
if [ -z "$ARTISAN_FILE" ]; then
  echo "ERROR: Could not find Laravel 'artisan' file in the image."
  exit 1
fi
APP_DIR="$(dirname "$ARTISAN_FILE")"
cd "$APP_DIR"

# --- ensure a usable .env (prefer a Secret File from Render if provided) ---
if [ -f /etc/secrets/.env ]; then
  cp /etc/secrets/.env "$APP_DIR/.env"
else
  # Build a minimal .env from environment variables
  cat > "$APP_DIR/.env" <<EOF
APP_NAME=Cattr
APP_ENV=production
APP_KEY=${APP_KEY:-base64:o8hF3UQ4WjH7cP9rX5kLm1T2bA6vZ2cNqY3wR7uPjKs=}
APP_URL=${APP_URL:-http://localhost:10000}

DB_CONNECTION=${DB_CONNECTION:-mysql}
DB_HOST=${DB_HOST:?set DB_HOST env var}
DB_PORT=${DB_PORT:-4000}
DB_DATABASE=${DB_DATABASE:-cattr}
DB_USERNAME=${DB_USERNAME:?set DB_USERNAME env var}
DB_PASSWORD=${DB_PASSWORD:?set DB_PASSWORD env var}

# TiDB SSL (safe defaults)
DB_SSL_CA=/etc/ssl/certs/ca-certificates.crt
DB_SSL_MODE=VERIFY_IDENTITY
EOF
fi

# --- clear caches so Laravel definitely reads our DB settings ---
php artisan config:clear || true
php artisan cache:clear  || true
php artisan route:clear  || true
php artisan view:clear   || true

# --- run migrations + seed against TiDB ---
php artisan migrate --force || true
php artisan db:seed --force || true

# --- run the app (Render provides $PORT) ---
php artisan serve --host=0.0.0.0 --port="${PORT:-10000}"
