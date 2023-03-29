#!/bin/bash

set -e

WORKING_DIR=${WORKING_DIR:-/etc/ssl}
S3_SSL_BUCKET=${S3_SSL_BUCKET:-"nerves-hub-$ENVIRONMENT-ca"}

mkdir -p $WORKING_DIR
aws s3 sync s3://$S3_SSL_BUCKET/ssl $WORKING_DIR
