#!/bin/sh
set -e

# Copy DB and static files to shared volume so sttmountaincrazy can access them.
# This runs every startup so the volume always has the latest data.
mkdir -p /data/static/gpx /data/static/maps /data/static/previews
cp -r /app/app/static/. /data/static/

exec uvicorn app.main:app --host 0.0.0.0 --port 8000
