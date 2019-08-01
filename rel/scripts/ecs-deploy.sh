#!/bin/bash

set -euo pipefail

CLUSTER=$1
SERVICE_NAME=$2
IMAGE=$3
MIN_PERCENTAGE=${4:-100}
MAX_PERCENTAGE=${5:-200}

if [ -z "$IMAGE" ]; then
  echo "Please include a image to deploy."
  exit 1
fi

echo "Deploying $SERVICE_NAME to $CLUSTER..."
echo "================="
ecs-deploy --cluster $CLUSTER \
           --service-name $SERVICE_NAME \
           --image $IMAGE \
           --timeout 720 \
           --min $MIN_PERCENTAGE \
           --max $MAX_PERCENTAGE \
           --enable-rollback \
           --max-definitions 50
echo "================="
