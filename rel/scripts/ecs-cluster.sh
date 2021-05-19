#!/bin/bash

set -e

SYNC_NODES_OPTIONAL=$(/app/ecs-sync-nodes.sh)
echo "$SYNC_NODES_OPTIONAL"
export SYNC_NODES_OPTIONAL

exec /app/bin/$APP_NAME start
