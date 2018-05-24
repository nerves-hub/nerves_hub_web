defmodule NervesHubClient.DeviceChannel do
  use PhoenixChannelClient
  require Logger

  def handle_in(event, payload, state) do
    Logger.info("Handle In: #{inspect(event)} #{inspect(payload)}")
    {:noreply, state}
  end

  def handle_reply(
        {:ok, :join, %{"response" => %{"serial" => serial}, "status" => "ok"}, _},
        state
      ) do
    state = Map.put(state, :serial, serial)
    Logger.info("Joined channel as #{serial}")
    {:noreply, state}
  end

  def handle_reply(payload, state) do
    Logger.info("Handle Reply: #{inspect(payload)}")
    {:noreply, state}
  end

  def handle_close(payload, state) do
    Logger.info("Handle close: #{inspect(payload)}")
    {:noreply, state}
  end
end
