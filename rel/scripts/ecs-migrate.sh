#!/bin/bash

set -e

VPC=$1
CLUSTER=$2
TASK=$3
SG=$4

task_status() {
  aws ecs describe-tasks --tasks $1 --cluster $CLUSTER | jq -r '.tasks[] .containers[0] .lastStatus'
}

task_exit_code() {
  aws ecs describe-tasks --tasks $1 --cluster $CLUSTER | jq -r '.tasks[] .containers[0] .exitCode'
}

SCRIPT_PATH=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )

# Construct the network configuration
NETWORK_CONFIGURATION=$($SCRIPT_PATH/ecs-network-configuration.sh $VPC $SG)

# Run any pending migrations
MIGRATION_TASK=$(aws ecs run-task \
  --cluster $CLUSTER \
  --count 1 \
  --started-by circle-ci \
  --task-definition $TASK \
  --overrides file://rel/scripts/migration-overrides.json \
  --launch-type FARGATE \
  --network-configuration $NETWORK_CONFIGURATION)

MIGRATION_TASK_ARN=$(echo $MIGRATION_TASK | jq -r '.tasks[0] .taskArn')
FINISHED=false

until $FINISHED; do
  STATUS=$(task_status $MIGRATION_TASK_ARN)
  if [ "$STATUS"  = "STOPPED" ]; then
    EXIT_CODE=$(task_exit_code $MIGRATION_TASK_ARN)
    echo "Migration Complete"
    echo "Exit code: $EXIT_CODE"
    exit $EXIT_CODE
  else
    echo "Migration status $STATUS"
    sleep 5
  fi
done
