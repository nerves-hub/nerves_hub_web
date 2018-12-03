#!/bin/sh

echo "Starting GC"
$RELEASE_ROOT_DIR/bin/nerves_hub_www command Elixir.NervesHubWebCore.Release.Tasks gc
echo "Finished GC"
