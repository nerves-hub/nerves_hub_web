#!/bin/bash

set -e

CLUSTER=nerves-hub
SERVICE=nerves-hub

METADATA=`curl http://169.254.170.2/v2/metadata`
export LOCAL_IPV4=$(echo $METADATA | jq -r '.Containers[0] .Networks[] .IPv4Addresses[0]')
export AWS_REGION_NAME=us-east-1

# We need to know what other nodes to hit to bring up the cluster. To do this we
# need to get a list of all other EC2 private DNS names, because that's how we build the node names

# get all tasks that are running
TASKS=$(aws ecs list-tasks --cluster $CLUSTER --service-name $SERVICE --output json | jq -r '.taskArns[]')
IP_ADDRESSES=$(aws ecs describe-tasks --cluster $CLUSTER --tasks $TASKS --output json | jq -r '.tasks[] .containers[] .networkInterfaces[] .privateIpv4Address')

# formatting
NODES=$(for IP in $IP_ADDRESSES; do echo "'nerves_hub@$IP'"; done)
NODES=$(echo $NODES | sed -e "s/ /, /g")
NODE_STRING="[$NODES]"

# we should now have something that looks like
# ['nerves_hub@10.0.2.120', 'nerves_hub@10.0.3.99']
export SYNC_NODES_OPTIONAL="$NODE_STRING"
echo $SYNC_NODES_OPTIONAL

exec nerves_hub foreground
