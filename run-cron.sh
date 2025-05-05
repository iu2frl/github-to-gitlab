#!/bin/bash
echo "Setting environment variables..."
env > /etc/environment
echo "Starting cron service..."
cron -f
echo "Cron exited with code $?"
