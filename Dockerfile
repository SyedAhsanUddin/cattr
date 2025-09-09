FROM amazingcat/cattr:latest

# Try to stop bundled MySQL; not critical if it still logs
RUN rm -f /etc/supervisor/conf.d/mysql.conf || true

# Keep your .env copy (fine to keep; env vars will still override)
COPY .env /var/www/html/.env

# Add our start script
COPY start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh

# Use our startup (runs migrate/seed, then serves)
CMD ["/usr/local/bin/start.sh"]

