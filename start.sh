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
  # Build a DSN that forces TLS for TiDB if not provided
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
APP_KEY=\${APP_KEY:-base64:o8hF3UQ4WjH7cP9rX5kLm1T2bA6vZ2cNqY3wR7uPjKs=}
APP_URL=\${APP_URL:-http://localhost:10000}

# Laravel prefers this DSN; includes ssl-mode for TiDB
DATABASE_URL=${DATABASE_URL}

# Classic vars (kept for compatibility)
DB_CONNECTION=\${DB_CONNECTION:-mysql}
DB_HOST=\${DB_HOST:-gateway01.ap-southeast-1.prod.aws.tidbcloud.com}
DB_PORT=\${DB_PORT:-4000}
DB_DATABASE=\${DB_DATABASE:-cattr}
DB_USERNAME=\${DB_USERNAME:-}
DB_PASSWORD=\${DB_PASSWORD:-}

# Tell PDO which CA bundle to use
MYSQL_ATTR_SSL_CA=\${MYSQL_ATTR_SSL_CA:-/etc/ssl/certs/ca-certificates.crt}
EOF
fi

# --- Make sure .env has LF line endings ---
sed -i 's/\r$//' "$APP_DIR/.env" || true

# --- Force TLS in Laravel config if not present (patch config/database.php) ---
DBCFG="$APP_DIR/config/database.php"
if [ -f "$DBCFG" ] && ! grep -q "PDO::MYSQL_ATTR_SSL_CA" "$DBCFG"; then
  cp "$DBCFG" "$DBCFG.bak" || true
  awk '
    BEGIN{inmysql=0; hasopt=0}
    {
      print
      if ($0 ~ /'\''mysql'\''[[:space:]]*=>[[:space:]]*\[/) { inmysql=1; next }
      if (inmysql==1 && $0 ~ /options[[:space:]]*=>/) { hasopt=1 }
      if (inmysql==1 && $0 ~ /\],[[:space:]]*$/) {
        if (hasopt==0) {
          print "            '\''options'\'' => extension_loaded('\''pdo_mysql'\'') ? array_filter([PDO::MYSQL_ATTR_SSL_CA => env('\''MYSQL_ATTR_SSL_CA'\'', '\''/etc/ssl/certs/ca-certificates.crt'\''),]) : [],"
        }
        inmysql=0
      }
    }
  ' "$DBCFG" > "$DBCFG.tmp" && mv "$DBCFG.tmp" "$DBCFG"
fi

# --- Clear caches so it reads the new env/config ---
php artisan config:clear || true
php artisan cache:clear  || true
php artisan route:clear  || true
php artisan view:clear   || true

# --- Create schema + seed on TiDB (don’t fail the whole boot if it flakes) ---
php artisan migrate --force || true
php artisan db:seed --force || true

# --- Run the app (Render provides $PORT) ---
php artisan serve --host=0.0.0.0 --port="${PORT:-10000}"
