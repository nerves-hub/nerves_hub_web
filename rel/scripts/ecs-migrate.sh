#!/bin/bash

set -e

CLUSTER=$1
TASK=$2

SCRIPT_PATH=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )

# Construct the network configuration
NETWORK_CONFIGURATION=$($SCRIPT_PATH/ecs-network-configuration.sh)

# Run any pending migrations
aws ecs run-task \
  --cluster $CLUSTER \
  --count 1 \
  --started-by circle-ci \
  --task-definition $TASK \
  --overrides file://rel/scripts/migration-overrides.json \
  --launch-type FARGATE \
  --network-configuration $NETWORK_CONFIGURATION
