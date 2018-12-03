#!/bin/sh

echo "Starting GC Firmware"
$RELEASE_ROOT_DIR/bin/nerves_hub_www command Elixir.NervesHubWebCore.Firmwares.GC run
echo "Finished GC Firmware"
