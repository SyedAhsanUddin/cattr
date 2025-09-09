FROM amazingcat/cattr:latest

# Remove MySQL startup script if present
RUN rm -f /etc/supervisor/conf.d/mysql.conf || true

# Copy our .env into the app
COPY .env /var/www/html/.env

# Expose Cattr’s Laravel web app only (no MySQL)
CMD ["php", "artisan", "serve", "--host=0.0.0.0", "--port=10000"]
