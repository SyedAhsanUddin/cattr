# Use the official Cattr image as a base
FROM amazingcat/cattr:latest

# Kill any inherited entrypoint that starts the built-in MySQL
ENTRYPOINT []

# Best-effort: remove supervisor configs that may start MySQL
RUN rm -f /etc/supervisor/conf.d/*mysql*.conf || true

# Add our startup script
COPY start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh

# Start only Laravel (our script finds artisan, runs migrations, then serves)
CMD ["/usr/local/bin/start.sh"]
