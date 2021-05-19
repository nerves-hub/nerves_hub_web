#!/bin/bash

VPC=nerves-hub-production
CLUSTER=nerves-hub-production
SG=nerves-hub-production-web-sg
TASK=nerves-hub-production-www

task_status() {
  aws ecs describe-tasks --tasks $1 --cluster $CLUSTER | jq -r '.tasks[] .containers[0] .lastStatus'
}

wait_for_container() {
    TASK_ARN=$1
    FINISHED=false

    until $FINISHED; do
        STATUS=$(task_status $TASK_ARN)
        if [ "$STATUS"  = "RUNNING" ]; then
            echo "Connect container is running"
            return
        elif [ "$STATUS"  = "STOPPED" ]; then
            echo "Connect container stopped"
            exit -1
        else
            echo "Container status $STATUS"
            sleep 5
        fi
    done
}


SCRIPT_PATH=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )

# Construct the network configuration
NETWORK_CONFIGURATION=$($SCRIPT_PATH/ecs-network-configuration.sh $VPC $SG)

CONNECT_TASK=$(aws ecs run-task \
  --cluster $CLUSTER \
  --count 1 \
  --started-by command-line \
  --task-definition $TASK \
  --launch-type FARGATE \
  --enable-execute-command \
  --network-configuration $NETWORK_CONFIGURATION)

CONNECT_TASK_ARN=$(echo $CONNECT_TASK | jq -r '.tasks[0] .taskArn')

wait_for_container $CONNECT_TASK_ARN
sleep 30

set -x

aws ecs execute-command  \
    --cluster $CLUSTER \
    --task $CONNECT_TASK_ARN \
    --command "/bin/bash" \
    --container nerves_hub_www \
    --interactive

aws ecs stop-task \
  --cluster $CLUSTER \
  --task $CONNECT_TASK_ARN \
  --reason "done"

# To setup device limits run /app/update-org-limits.sh