#!/bin/bash

set -e

SCRIPT_PATH=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )

$SCRIPT_PATH/s3-sync.sh

exec $@
