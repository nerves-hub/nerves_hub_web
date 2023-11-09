#!/bin/bash

set -e

service_ip_addresses() {
  SERVICE=$1

  EXISTS=$(aws ecs describe-services --cluster $CLUSTER --services $SERVICE | jq -r 'select(.services | length > 0)')
  if [ ! -z "$EXISTS" ]; then
    # get all tasks that are running
    TASKS=$(aws ecs list-tasks --cluster $CLUSTER --service-name $SERVICE --output json | jq -r '.taskArns[]')
    if [ ! -z "$TASKS" ]; then
      aws ecs describe-tasks --cluster $CLUSTER --tasks $TASKS --output json | jq -r '.tasks[] .containers[] .networkInterfaces[] .privateIpv4Address'
    fi
  fi
}

format_nodes() {
  for IP in $1; do echo "nerves_hub@$IP"; done
}

METADATA=`curl $ECS_CONTAINER_METADATA_URI`
export LOCAL_IPV4=$(echo $METADATA | jq -r '.Networks[0] .IPv4Addresses[0]')
export AWS_REGION_NAME=us-east-1

if [[ -z ${WWW_SERVICE} ]]; then
  export WWW_SERVICE="nerves-hub-www"
fi
if [[ -z ${DEVICE_SERVICE} ]]; then
  export DEVICE_SERVICE="nerves-hub-device"
fi

WWW_IPS=$(service_ip_addresses ${WWW_SERVICE})
WWW_NODES=$(format_nodes "$WWW_IPS")

DEVICE_IPS=$(service_ip_addresses ${DEVICE_SERVICE})
DEVICE_NODES=$(format_nodes "$DEVICE_IPS")

NODES=$(echo "$DEVICE_NODES $WWW_NODES" | tr '\n' ' ')

# we should now have something that looks like
# nerves_hub_www@10.0.2.120 nerves_hub_device@10.0.3.99 nerves_hub_api@10.0.3.101
export SYNC_NODES_OPTIONAL="$NODES"
echo "SYNC_NODES_OPTIONAL=${SYNC_NODES_OPTIONAL}"

exec /app/bin/nerves_hub start
