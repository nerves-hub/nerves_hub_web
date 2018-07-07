#!/bin/sh

echo "Starting migration"
$RELEASE_ROOT_DIR/bin/nerves_hub command Elixir.NervesHub.Release.Tasks migrate
echo "Finished migration"

echo "Starting seeds"
$RELEASE_ROOT_DIR/bin/nerves_hub command Elixir.NervesHub.Release.Tasks seed
echo "Finished seeds"
