FROM amazingcat/cattr:latest
ENTRYPOINT []
RUN rm -f /etc/supervisor/conf.d/*mysql*.conf || true
COPY start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh && sed -i 's/\r$//' /usr/local/bin/start.sh
CMD ["/usr/local/bin/start.sh"]
