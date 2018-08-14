# Client Server Communication

This document outlines the basic communication protocol between a Nerves device
and NervesHubWWW. At a high level, the device connects to NervesHub over a
websocket connection, authenticates with a certificate, and is able to receive
commands and send updates about its current state.

## Joining the Device Channel

After booting, the client connects to NervesHub with its certificate. The
certificate is used to determine the unique identity of the device, which is
then stored on the socket. The device joins `device:#{firmware_uuid}`.  
The server compares the running version of the firmware
to the target version for that device on `NervesHub`. If those versions are
different, then the channel queues a firmware update message to be sent as soon
as the channel finishes the join process. The final step of the join process is
to respond to the device with a list of the group channels that it should join.

## Joining Group Channels

If the client receives a group channel from the device channel, it will attempt
to join it. Authorization to join the group channel for that org and product
are verified by checking the device's associations in the database. These
channels provide the same interface as the individual device channels, but allow
bulk management of devices. Group channels are named using the format
`group:#{org}:#{product}:#{group_name}`.

## Joining and Leaving Groups

If a user adds or removes a device from a group while the device is connected,
the server sends a message to join or leave the group channel. Messages to join
and leave a channel look like `{"join", channel_name}` and `{"leave",
channel_name}` respectively. If a user deletes a group, all members will receive
a `{"leave", channel_name}` message.

## Updating Firmware

If the target version changes for a device or group of devices, the channel will
issue an `{"firmware_update", %{"url" => update_url, "version" => version}`
message to either the individual device channel, or the group channel. This will
tell the firmware to start streaming the `.fw` file to the
`Nerves.Firmware.Fwup` client. If the device is already on the version that it
was instructed to update the firmware to, which may happen in groups, the device
ignores the update command.

If the client determines that it should update to the provided firmware image.
It will send updates to the device channel when it begins and finishes applying
the update and before it reboots. If there are any issues downloading or
applying the update, those are sent back as `{"firmware_update_error",
%{"errors" => [errors]}}`.


## Extensibility

Commands can be added in subsequent releases at the device or group level to add
new commands like requesting logs or rebooting a device.
