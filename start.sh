#!/bin/sh
set -e

# --- Locate the Laravel app ---
ARTISAN_FILE="$(find / -type f -name artisan 2>/dev/null | head -n1)"
if [ -z "$ARTISAN_FILE" ]; then
  echo "ERROR: Could not find Laravel 'artisan' file."
  exit 1
fi
APP_DIR="$(dirname "$ARTISAN_FILE")"
cd "$APP_DIR"

# --- Prefer Render secret .env; else generate from env vars ---
if [ -f /etc/secrets/.env ]; then
  cp /etc/secrets/.env "$APP_DIR/.env"
else
  : "${DB_CONNECTION:=mysql}"
  : "${DB_HOST:=gateway01.ap-southeast-1.prod.aws.tidbcloud.com}"
  : "${DB_PORT:=4000}"
  : "${DB_DATABASE:=cattr}"
  : "${DB_USERNAME:=}"
  : "${DB_PASSWORD:=}"

  # If user didn’t provide, build a TLS DSN for TiDB:
  if [ -z "$DATABASE_URL" ]; then
    DATABASE_URL="${DB_CONNECTION}://${DB_USERNAME}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_DATABASE}?ssl-mode=VERIFY_IDENTITY"
  fi

  cat > "$APP_DIR/.env" <<EOF
APP_NAME=Cattr
APP_ENV=production
APP_KEY=${APP_KEY:-base64:o8hF3UQ4WjH7cP9rX5kLm1T2bA6vZ2cNqY3wR7uPjKs=}
APP_URL=${APP_URL:-https://cattr-wtvq.onrender.com}

# Primary DSN (includes TLS for TiDB)
DATABASE_URL=${DATABASE_URL}

# Classic vars (kept for packages that still read them)
DB_CONNECTION=${DB_CONNECTION}
DB_HOST=${DB_HOST}
DB_PORT=${DB_PORT}
DB_DATABASE=${DB_DATABASE}
DB_USERNAME=${DB_USERNAME}
DB_PASSWORD=${DB_PASSWORD}

# CA bundle for PDO TLS
MYSQL_ATTR_SSL_CA=${MYSQL_ATTR_SSL_CA:-/etc/ssl/certs/ca-certificates.crt}
EOF
fi

# Normalize line endings just in case
sed -i 's/\r$//' "$APP_DIR/.env" || true

# --- Force TLS in Laravel mysql driver (adds PDO::MYSQL_ATTR_SSL_CA) ---
DBCFG="$APP_DIR/config/database.php"
if [ -f "$DBCFG" ] && ! grep -q "PDO::MYSQL_ATTR_SSL_CA" "$DBCFG"; then
  cp "$DBCFG" "$DBCFG.bak" || true
  awk '
    BEGIN{inmysql=0; hasopt=0}
    { print }
    $0 ~ /'\''mysql'\''[[:space:]]*=>[[:space:]]*\[/ { inmysql=1; next }
    inmysql==1 && $0 ~ /options[[:space:]]*=>/ { hasopt=1 }
    inmysql==1 && $0 ~ /\],[[:space:]]*$/ {
      if (hasopt==0) {
        print "            '\''options'\'' => extension_loaded('\''pdo_mysql'\'') ? array_filter([PDO::MYSQL_ATTR_SSL_CA => env('\''MYSQL_ATTR_SSL_CA'\'', '\''/etc/ssl/certs/ca-certificates.crt'\''),]) : [],"
      }
      inmysql=0
    }
  ' "$DBCFG" > "$DBCFG.tmp" && mv "$DBCFG.tmp" "$DBCFG"
fi

# --- TiDB workaround: skip migrations that try to CREATE/DROP TRIGGER ---
if [ -d "$APP_DIR/database/migrations" ]; then
  TRIGGER_MIGS="$(grep -RIlE 'CREATE[[:space:]]+TRIGGER|DROP[[:space:]]+TRIGGER' "$APP_DIR/database/migrations" || true)"
  if [ -n "$TRIGGER_MIGS" ]; then
    echo "TiDB detected: disabling trigger migrations:"
    echo "$TRIGGER_MIGS" | while read -r f; do
      [ -f "$f" ] || continue
      echo " - skipping $f"
      cp "$f" "$f.bak" || true
      mv "$f" "$f.tidb-skip"
    done
  fi
fi

# --- Clear caches so config/env changes take effect ---
php artisan config:clear || true
php artisan cache:clear  || true
php artisan route:clear  || true
php artisan view:clear   || true

# --- Run schema + seed (continue even if a step flakes once) ---
php artisan migrate --force || true
php artisan db:seed --force || true

# --- Start the app (Render sets \$PORT) ---
php artisan serve --host=0.0.0.0 --port="${PORT:-10000}"
