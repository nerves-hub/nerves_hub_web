#!/bin/bash

set -e

WORKING_DIR=${WORKING_DIR:-/etc/ssl}
S3_BUCKET=${S3_BUCKET:-'nerves-hub-ca'}

mkdir -p $WORKING_DIR
aws s3 sync s3://$S3_BUCKET $WORKING_DIR
