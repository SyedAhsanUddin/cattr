#!/bin/sh
set -e

# --- Locate Laravel app ---
ARTISAN_FILE="$(find / -type f -name artisan 2>/dev/null | head -n1)"
if [ -z "$ARTISAN_FILE" ]; then
  echo "ERROR: Could not find Laravel 'artisan'."
  exit 1
fi
APP_DIR="$(dirname "$ARTISAN_FILE")"
cd "$APP_DIR"

# --- Use Render secret .env if present, otherwise compose one from env vars ---
if [ -f /etc/secrets/.env ]; then
  cp /etc/secrets/.env "$APP_DIR/.env"
else
  : "${APP_URL:=https://cattr-wtvq.onrender.com}"

  : "${DB_CONNECTION:=mysql}"
  : "${DB_HOST:=gateway01.ap-southeast-1.prod.aws.tidbcloud.com}"
  : "${DB_PORT:=4000}"
  : "${DB_DATABASE:=cattr}"
  : "${DB_USERNAME:=}"
  : "${DB_PASSWORD:=}"

  # Build a TLS DSN for TiDB (Serverless requires TLS)
  if [ -z "$DATABASE_URL" ]; then
    DATABASE_URL="${DB_CONNECTION}://${DB_USERNAME}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_DATABASE}?ssl-mode=VERIFY_IDENTITY"
  fi

  cat > "$APP_DIR/.env" <<EOF
APP_NAME=Cattr
APP_ENV=production
APP_KEY=${APP_KEY:-base64:o8hF3UQ4WjH7cP9rX5kLm1T2bA6vZ2cNqY3wR7uPjKs=}
APP_URL=${APP_URL}

DATABASE_URL=${DATABASE_URL}

DB_CONNECTION=${DB_CONNECTION}
DB_HOST=${DB_HOST}
DB_PORT=${DB_PORT}
DB_DATABASE=${DB_DATABASE}
DB_USERNAME=${DB_USERNAME}
DB_PASSWORD=${DB_PASSWORD}

MYSQL_ATTR_SSL_CA=${MYSQL_ATTR_SSL_CA:-/etc/ssl/certs/ca-certificates.crt}
EOF
fi
sed -i 's/\r$//' "$APP_DIR/.env" || true

# --- Ensure mysql driver uses TLS (PDO::MYSQL_ATTR_SSL_CA) ---
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

# --- TiDB: skip migrations that create/drop triggers (unsupported) ---
if [ -d "$APP_DIR/database/migrations" ]; then
  # BusyBox grep: use -r (not -R)
  TRIGGER_MIGS="$(grep -rilE 'CREATE[[:space:]]+TRIGGER|DROP[[:space:]]+TRIGGER' "$APP_DIR/database/migrations" 2>/dev/null || true)"
  if [ -n "$TRIGGER_MIGS" ]; then
    echo "TiDB: disabling trigger migrations:"
    echo "$TRIGGER_MIGS" | while read -r f; do
      [ -f "$f" ] || continue
      echo " - skipping $f"
      cp "$f" "$f.bak" 2>/dev/null || true
      mv "$f" "$f.tidb-skip"
    done
  fi

  # Skip the noisy duplicate-index migration that blocks later ones
  for f in "$APP_DIR"/database/migrations/*add_index*.php; do
    [ -f "$f" ] || continue
    echo "Disabling known duplicate-index migration: $f"
    cp "$f" "$f.bak" 2>/dev/null || true
    mv "$f" "$f.tidb-skip"
  done
fi

# --- Clear caches so config/env changes take effect ---
php artisan config:clear || true
php artisan cache:clear  || true
php artisan route
