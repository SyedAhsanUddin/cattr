#!/usr/bin/env bash
set -e

cd /var/www/html

# Make sure Laravel uses the env vars we provided
php artisan config:clear
php artisan cache:clear
php artisan route:clear
php artisan view:clear

# Run migrations/seeders against the configured DB (TiDB)
php artisan migrate --force || true
php artisan db:seed --force || true

# Start the app (Render will route to this port)
php artisan serve --host=0.0.0.0 --port=${PORT:-10000}
