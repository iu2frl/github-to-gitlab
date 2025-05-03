FROM debian:bookworm
 
 # Install tools
 RUN apt-get update && \
     apt-get install -y git curl jq cron && \
     apt-get clean
 
 # Copy files
 COPY mirror.sh /mirror.sh
 COPY crontab.txt /etc/cron.d/mirror-cron
 
 RUN chmod +x /mirror.sh && chmod 0644 /etc/cron.d/mirror-cron && \
     crontab /etc/cron.d/mirror-cron
 
 # Create log file
 RUN touch /var/log/mirror.log
 
 CMD cron -f
