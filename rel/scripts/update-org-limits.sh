#!/bin/bash

ORG_NAME=$1
DEVICES=$2

export AWS_ENV_PATH=/nerves_hub_www/production/
eval $(aws-env)

SYNC_NODES_OPTIONAL=$(/app/ecs-sync-nodes.sh)
export SYNC_NODES_OPTIONAL="$SYNC_NODES_OPTIONAL"

# /app/bin/nerves_hub_www remote
/app/bin/nerves_hub_www rpc "with {:ok, org} <- NervesHubWebCore.Accounts.get_org_by_name(\"$ORG_NAME\"), do: NervesHubWebCore.Accounts.get_org_limit_by_org_id(org.id) |> NervesHubWebCore.Accounts.update_org_limit(%{devices: $DEVICES, org_id: org.id})"