#!/bin/bash
set -e

export APP_NAME=nerves_hub_www
export VPC=nerves-hub-production
export CLUSTER=nerves-hub-production
export TASK=nerves-hub-production-www
export TASK_SG=nerves-hub-production-web-sg
export SERVICE=nerves-hub-www

NERVES_HUB_WWW_TASK=$(rel/scripts/ecs-update-task.sh $TASK 221489699002.dkr.ecr.eu-central-1.amazonaws.com/sportalliance/nerves-hub-www:latest)
rel/scripts/ecs-migrate.sh \
    $VPC \
    $CLUSTER \
    $NERVES_HUB_WWW_TASK \
    $TASK_SG