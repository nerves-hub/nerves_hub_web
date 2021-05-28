#!/bin/bash

set -e

export SYNC_NODES_OPTIONAL=$(/app/ecs-sync-nodes.sh)
echo "$SYNC_NODES_OPTIONAL"
export LOCAL_IPV4=$(/app/ecs-local-ipv4.sh)
echo "$LOCAL_IPV4"

exec /app/bin/$APP_NAME start
