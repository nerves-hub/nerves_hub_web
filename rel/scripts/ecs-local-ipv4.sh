#!/bin/bash

set -e

METADATA=`curl -s $ECS_CONTAINER_METADATA_URI`
LOCAL_IPV4=$(echo $METADATA | jq -r '.Networks[0] .IPv4Addresses[0]')
echo $LOCAL_IPV4
