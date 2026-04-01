defmodule NervesHub.Telemetry.CustomizationsTest do
  use ExUnit.Case, async: true

  alias NervesHub.Telemetry.Customizations

  describe "handle_request/4" do
    test "handles websocket request with conn" do
      conn = %{request_path: "/socket/websocket"}
      metadata = %{conn: conn}

      assert :ok = Customizations.handle_request([:bandit, :request, :stop], %{}, metadata, nil)
    end

    test "handles non-websocket request with conn" do
      conn = %{request_path: "/api/devices"}
      metadata = %{conn: conn}

      assert :ok = Customizations.handle_request([:bandit, :request, :stop], %{}, metadata, nil)
    end

    test "handles timeout error without conn" do
      metadata = %{
        error: "Unrecoverable error: timeout",
        plug: {NervesHubWeb.DeviceEndpoint, []},
        telemetry_span_context: make_ref(),
        connection_telemetry_span_context: make_ref()
      }

      assert :ok = Customizations.handle_request([:bandit, :request, :stop], %{}, metadata, nil)
    end

    test "handles empty metadata" do
      assert :ok = Customizations.handle_request([:bandit, :request, :stop], %{}, %{}, nil)
    end
  end
end
