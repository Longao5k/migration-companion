#!/bin/sh
set -eu

while true; do
  curl --fail --silent --show-error --request POST \
    --header "x-worker-key: ${WORKER_API_KEY}" \
    http://api:3000/v1/file-worker/cleanup-expired-uploads || true
  curl --fail --silent --show-error --request POST \
    --header "x-worker-key: ${WORKER_API_KEY}" \
    http://api:3000/v1/account-worker/run-due-deletions || true
  sleep "${MAINTENANCE_INTERVAL_SECONDS:-3600}"
done
