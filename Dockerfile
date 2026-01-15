FROM alpine:3.19

# Install tools
RUN apk add --no-cache git curl jq bash dcron

# Copy files
COPY mirror.sh /root/mirror.sh
COPY run-cron.sh /root/run-cron.sh
COPY crontab.txt /root/crontab.txt

RUN chmod +x /root/mirror.sh && \
    chmod +x /root/run-cron.sh

# Setup cron
RUN crontab /root/crontab.txt

# Prepare repos path
RUN mkdir -p /root/repos

# Set entrypoint
ENTRYPOINT ["/bin/bash"]
CMD ["/root/run-cron.sh"]
