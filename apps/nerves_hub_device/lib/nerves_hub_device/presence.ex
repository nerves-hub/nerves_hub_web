defmodule NervesHubDevice.Presence do
  use Phoenix.Presence,
    otp_app: :nerves_hub_device,
    pubsub_server: NervesHubWeb.PubSub
end
