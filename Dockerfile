FROM debian:bookworm

# Install tools
RUN apt-get update && \
    apt-get install -y git curl jq cron && \
    apt-get clean

# Copy files
COPY mirror.sh /root/mirror.sh
COPY run-cron.sh /root/run-cron.sh
COPY crontab.txt /etc/cron.d/mirror-cron

RUN chmod +x /root/mirror.sh
RUN chmod +x /root/run-cron.sh

# Add crontab file in the cron.d directory
RUN chmod 0644 /etc/cron.d/mirror-cron
RUN crontab /etc/cron.d/mirror-cron

# Prepare repos path
RUN mkdir -p /root/repos

# Set entrypoint
ENTRYPOINT ["/bin/bash", "/root/run-cron.sh"]
