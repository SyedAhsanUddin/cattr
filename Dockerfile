FROM amazingcat/cattr:latest

# Set the working directory to the public directory of your Laravel app
WORKDIR /app/backend/public

# Remove unnecessary mysql config
RUN rm -f /etc/supervisor/conf.d/*mysql*.conf || true

# Copy start.sh script and give execution permissions
COPY start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh && sed -i 's/\r$//' /usr/local/bin/start.sh

# Start the application
CMD ["/usr/local/bin/start.sh"]
