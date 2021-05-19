#!/bin/bash

set -e

VPC=$1
SG=$2

VPCS=$(aws ec2 describe-vpcs --output json | jq ".Vpcs")
VPC=$(echo $VPCS | jq --arg vpc $VPC '.[] | select((.Tags[]|select(.Key=="Name")|.Value) == $vpc) | .VpcId')
SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC" --output json | jq -c '[.Subnets[] | select((.Tags[]|select(.Key=="Name")|.Value) | (contains("private")) or contains("db")) | .SubnetId]')
SECURITY_GROUPS=$(aws ec2 describe-security-groups --filters=Name=tag:Name,Values=$SG | jq -c '[.SecurityGroups[] | .GroupId ]')

echo "awsvpcConfiguration={subnets=$SUBNETS,securityGroups=$SECURITY_GROUPS,assignPublicIp=ENABLED}"
