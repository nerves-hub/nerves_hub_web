#!/bin/bash
set -e

export VPC=nerves-hub-production
export CLUSTER=nerves-hub-production

MODULES=(
    www
    api
    device
)

for MODULE in "${MODULES[@]}"
do
    export IMAGE_NAME="nerves-hub-${MODULE}"
    export APP_NAME="nerves_hub_${MODULE}"
    export TASK="nerves-hub-production-${MODULE}"
    export TASK_SG="nerves-hub-production-${MODULE}-sg"
    export SERVICE="nerves-hub-${MODULE}"
    rel/scripts/ecs-deploy.sh \
        $CLUSTER \
        $SERVICE \
        221489699002.dkr.ecr.eu-central-1.amazonaws.com/sportalliance/$IMAGE_NAME:latest &
done
wait
