#!/bin/sh
set -e

# --- Find the Laravel app (where 'artisan' lives) ---
ARTISAN_FILE="$(find / -type f -name artisan 2>/dev/null | head -n1)"
if [ -z "$ARTISAN_FILE" ]; then
  echo "ERROR: Could not find Laravel 'artisan' file in the image."
  exit 1
fi
APP_DIR="$(dirname "$ARTISAN_FILE")"
cd "$APP_DIR"

# --- Use Secret File .env if provided by Render, else write one from env vars ---
if [ -f /etc/secrets/.env ]; then
  cp /etc/secrets/.env "$APP_DIR/.env"
else
  # If a full DSN wasn't provided, synthesize one that forces TLS for TiDB
  if [ -z "$DATABASE_URL" ]; then
    : "${DB_CONNECTION:=mysql}"
    : "${DB_HOST:=gateway01.ap-southeast-1.prod.aws.tidbcloud.com}"
    : "${DB_PORT:=4000}"
    : "${DB_DATABASE:=cattr}"
    : "${DB_USERNAME:=}"
    : "${DB_PASSWORD:=}"
    DATABASE_URL="${DB_CONNECTION}://${DB_USERNAME}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_DATABASE}?ssl-mode=VERIFY_IDENTITY"
  fi

  cat > "$APP_DIR/.env" <<EOF
APP_NAME=Cattr
APP_ENV=production
APP_KEY=${APP_KEY:-base64:o8hF3UQ4WjH7cP9rX5kLm1T2bA6vZ2cNqY3wR7uPjKs=}
APP_URL=${APP_URL:-http://localhost:10000}

# Laravel will prefer this DSN (includes ssl-mode for TiDB)
DATABASE_URL=${DATABASE_URL}

# Keep classic vars too (Laravel still reads these if needed)
DB_CONNECTION=${DB_CONNECTION:-mysql}
DB_HOST=${DB_HOST:-gateway01.ap-southeast-1.prod.aws.tidbcloud.com}
DB_PORT=${DB_PORT:-4000}
DB_DATABASE=${DB_DATABASE:-cattr}
DB_USERNAME=${DB_USERNAME:-}
DB_PASSWORD=${DB_PASSWORD:-}

# Ensure PDO trusts system CAs (used by database.php -> options)
MYSQL_ATTR_SSL_CA=${MYSQL_ATTR_SSL_CA:-/etc/ssl/certs/ca-certificates.crt}
EOF
fi

# --- Make sure we don't have Windows CRLF messing us up ---
# (Not strictly needed here, but harmless safeguard)
find "$APP_DIR" -maxdepth 1 -name ".env" -exec sh -c "sed -i 's/\r$//' {}" \; || true

# --- Clear caches so it reads the new env ---
php artisan config:clear || true
php artisan cache:clear  || true
php artisan route:clear  || true
php artisan view:clear   || true

# --- Create schema + seed on TiDB (don't crash the whole app if it fails) ---
php artisan migrate --force || true
php artisan db:seed --force || true

# --- Run the app (Render provides \$PORT) ---
php artisan serve --host=0.0.0.0 --port="${PORT:-10000}"
