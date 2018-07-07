#!/bin/bash

set -e

TASK_NAME=$1
DOCKER_IMAGE=$2

# Get the previous task definition
OLD_TASK_DEF=$(aws ecs describe-task-definition --task-definition $TASK_NAME --output json)
OLD_TASK_DEF_REVISION=$(echo $OLD_TASK_DEF | jq ".taskDefinition|.revision")

# Swap in the new image
NEW_TASK_DEF=$(echo $OLD_TASK_DEF | jq --arg NDI $DOCKER_IMAGE '.taskDefinition.containerDefinitions[0].image=$NDI')

# Create a new task template with all the required information to bring over
FINAL_TASK=$(echo $NEW_TASK_DEF | jq '.taskDefinition|{family: .family, volumes: .volumes, containerDefinitions: .containerDefinitions, taskRoleArn: .taskRoleArn, executionRoleArn: .executionRoleArn, cpu: .cpu, memory: .memory, networkMode: .networkMode, requiresCompatibilities: .requiresCompatibilities}')

# Upload the task information and register the new task definition along with optional information
UPDATED_TASK=$(aws ecs register-task-definition --cli-input-json "$(echo $FINAL_TASK)")

# Store the Revision
UPDATED_TASK_DEF_REVISION=$(echo $UPDATED_TASK | jq -r '.taskDefinition|.taskDefinitionArn')
echo $UPDATED_TASK_DEF_REVISION
