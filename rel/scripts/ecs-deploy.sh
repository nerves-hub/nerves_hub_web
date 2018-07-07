#!/bin/bash

set -e

CLUSTER=$1
SERVICE=$2
TASK=$3

aws ecs update-service \
  --service $SERVICE \
  --cluster $CLUSTER \
  --task-definition $TASK
