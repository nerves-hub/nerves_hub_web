#!/bin/bash

set -e

VPCS=$(aws ec2 describe-vpcs --output json | jq ".Vpcs")
VPC=$(echo $VPCS | jq '.[] | . as $vpc | .Tags[] | select(.Key == "Name" and .Value == "nerves-hub") | $vpc.VpcId')

SUBNETS=$(aws ec2 describe-subnets --filters=Name=vpc-id,Values=$VPC,Name=tag:Name,Values=nerves-hub/Private --output json | jq -c '[.Subnets[] | .SubnetId]')
SECURITY_GROUPS=$(aws ec2 describe-security-groups --filters=Name=tag:Name,Values=nerves-hub-sg | jq -c '[.SecurityGroups[] | .GroupId ]')

echo "awsvpcConfiguration={subnets=$SUBNETS,securityGroups=$SECURITY_GROUPS,assignPublicIp=DISABLED}"
