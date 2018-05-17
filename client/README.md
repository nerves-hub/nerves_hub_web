# BeamwareClient

This directory contains a test client for interacting with the Beamware server
as a device.

First start the Beamware server, then build and start up an IEx session:

```sh
mix deps.get
iex -S mix
```

Connect as follows:

```elixir
iex> DeviceChannel.join
%{event: "phx_join", payload: %{}, ref: "1", topic: "device:lobby"}
17:14:28.037 [info]  Joined channel as hub-1234
```
