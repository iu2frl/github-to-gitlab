#!/bin/bash
echo "Setting environment variables..."

# Alpine/dcron requires environment variables to be exported explicitly for cron jobs
# We dump the current environment using export -p which handles quoting correctly
export -p > /root/container_env.sh
chmod +x /root/container_env.sh

# Check if we should run the sync immediately
if [ "$FORCE_SYNC_ON_START" = "true" ]; then
    echo "FORCE_SYNC_ON_START is set to true. Running synchronization immediately..."
    /root/mirror.sh
fi

echo "Starting cron service..."
# In Alpine, crond runs in foreground with -f, -l 2 captures logs to stdout
crond -f -l 2
