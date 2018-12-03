#!/bin/sh

echo "Starting migration"
$RELEASE_ROOT_DIR/bin/nerves_hub_www command Elixir.NervesHubWebCore.Release.Tasks migrate
echo "Finished migration"

echo "Starting seeds"
$RELEASE_ROOT_DIR/bin/nerves_hub_www command Elixir.NervesHubWebCore.Release.Tasks seed
echo "Finished seeds"
