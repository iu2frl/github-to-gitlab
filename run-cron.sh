#!/bin/bash
echo "Setting environment variables..."
env > /etc/environment

# Check if we should run the sync immediately
if [ "$FORCE_SYNC_ON_START" = "true" ]; then
    echo "FORCE_SYNC_ON_START is set to true. Running synchronization immediately..."
    /root/mirror.sh
fi

echo "Starting cron service..."
cron -f
echo "Cron exited with code $?"
