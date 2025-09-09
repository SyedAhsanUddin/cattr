FROM amazingcat/cattr:latest

# Stop any inherited entrypoint that might start MySQL
ENTRYPOINT []

# Best-effort: remove supervisor bits that start MySQL
RUN rm -f /etc/supervisor/conf.d/*mysql*.conf || true

# Add our startup script
COPY start.sh /usr/local/bin/start.sh

# Make it executable AND convert CRLF -> LF (fixes 'bash\r' / 'sh\r')
RUN chmod +x /usr/local/bin/start.sh && sed -i 's/\r$//' /usr/local/bin/start.sh

# Start ONLY Laravel via our script
CMD ["/usr/local/bin/start.sh"]
