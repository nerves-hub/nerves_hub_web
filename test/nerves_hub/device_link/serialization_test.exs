defmodule NervesHub.DeviceLink.SerializationTest do
  @moduledoc """
  Guards the state that travels between a device's connection and the platform.

  Everything DeviceLink hands back is held by whoever owns the connection and
  passed in again on the next call. While that caller is in the same VM, nothing
  stops the state quietly growing, or gaining something that cannot cross a wire
  at all — and it would keep working perfectly right up until a caller that is
  not in this VM tried to use it.

  So the bounds are asserted here rather than discovered later.
  """

  use ExUnit.Case, async: true

  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.DeviceLink.Session
  alias NervesHub.Extensions.ExternalIdentity
  alias NervesHub.Extensions.Geo
  alias NervesHub.Extensions.Health
  alias NervesHub.Extensions.LocalShell
  alias NervesHub.Extensions.Logging
  alias NervesHub.Extensions.State
  alias NervesHubWeb.Channels.Scrollback

  # Generous, but small enough to notice a structure being added by accident.
  @session_bytes 2_048

  defp device_info() do
    %DeviceInfo{
      allowed_extensions: [:health, :geo, :logging, :local_shell],
      connection_ref: Ecto.UUID.generate(),
      deployment_id: 4321,
      device_id: 1234,
      device_identifier: "some-fairly-long-device-identifier-0001",
      device_network_interface: :wifi,
      device_updates_blocked_until: DateTime.utc_now(),
      device_updates_enabled: true,
      firmware_metadata: %{
        uuid: Ecto.UUID.generate(),
        version: "1.2.3",
        platform: "rpi4",
        architecture: "arm64",
        product: "some-product"
      },
      org_id: 11,
      product_id: 22
    }
  end

  defp round_trip(term) do
    binary = :erlang.term_to_binary(term)
    {:erlang.binary_to_term(binary), byte_size(binary)}
  end

  test "a device session round trips unchanged and stays small" do
    session = %Session{
      device_info: device_info(),
      device_api_version: "2.2.0",
      currently_downloading_uuid: Ecto.UUID.generate(),
      deployment_topic: "deployment:4321",
      script_refs: %{"aB3dE9" => self()}
    }

    {restored, bytes} = round_trip(session)

    assert restored == session,
           "the device session did not survive a round trip"

    assert bytes < @session_bytes,
           "device session is #{bytes} bytes, over the #{@session_bytes} byte bound"
  end

  test "device info alone stays small" do
    info = device_info()
    {restored, bytes} = round_trip(info)

    # Around 760 bytes today: two UUIDs, the firmware metadata map, a timestamp.
    assert restored == info
    assert bytes < 1_024, "device info is #{bytes} bytes"
  end

  describe "extension state" do
    test "every extension's state stays small" do
      extensions = [
        Health,
        Geo,
        Logging,
        LocalShell,
        ExternalIdentity
      ]

      for extension <- extensions do
        state = State.new(device_info())
        {state, _effects} = extension.attach(state)

        {restored, bytes} = round_trip(state)

        assert restored == state
        assert bytes < @session_bytes, "#{inspect(extension)} state is #{bytes} bytes"
      end
    end

    test "local shell output does not accumulate in state that travels" do
      # Held on the connection instead, because a full scrollback measured
      # around 89KB and this state goes with every call. A device writing
      # steadily to its shell would otherwise resend its whole backlog per line.
      state = State.new(device_info())
      {state, _effects} = LocalShell.attach(state)

      line = String.duplicate("x", 80) <> "\n"

      {state, effects} =
        Enum.reduce(1..1200, {state, []}, fn _, {state, _} ->
          LocalShell.handle_in("shell_output", %{"data" => line}, state)
        end)

      assert effects == [{:scrollback_append, line}],
             "output should be handed to the connection, not kept"

      {_restored, bytes} = round_trip(state)

      assert bytes < @session_bytes,
             "local shell state grew to #{bytes} bytes after 1200 lines of output"
    end
  end

  test "scrollback keeps what was written, wherever it is held" do
    scrollback =
      Scrollback.new(4)
      |> Scrollback.append("one\ntwo\n")
      |> Scrollback.append("three\nfour\nfive\n")
      |> Scrollback.append("partial")

    # Bounded to the last 4 completed lines, plus the line still being written.
    assert Scrollback.text(scrollback) == "two\nthree\nfour\nfive\npartial"
  end
end
