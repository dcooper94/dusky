#!/usr/bin/env bash
# Start cliphist clipboard services with proper environment

# Source UWSM environment
if [[ -f ~/.config/uwsm/env ]]; then
    source ~/.config/uwsm/env
fi

# Kill existing processes
pkill -f "wl-paste.*cliphist" 2>/dev/null

# Wait a moment
sleep 1

# Start clipboard watchers
wl-paste --type text --watch cliphist store &
wl-paste --type image --watch cliphist store &

echo "Cliphist services started with CLIPHIST_DB_PATH=${CLIPHIST_DB_PATH}"
echo "Database location: ${CLIPHIST_DB_PATH:-~/.cache/cliphist/db (default)}"
