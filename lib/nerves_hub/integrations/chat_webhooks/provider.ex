defmodule NervesHub.Integrations.ChatWebhooks.Provider do
  @moduledoc """
  What a chat service brings to chat webhooks
  (`NervesHub.Integrations.ChatWebhooks`): which of its URLs are webhooks,
  and how its messages are built. Posting, batching and everything else is
  shared.

  Implemented by `NervesHub.Integrations.Teams` and
  `NervesHub.Integrations.Discord`.
  """

  @doc "The chat service's name, as people know it."
  @callback label() :: String.t()

  @doc "Whether `url` is one of the service's incoming webhooks, with a message for the form when not."
  @callback check_url(url :: String.t()) :: :ok | {:error, String.t()}

  @doc "The body posted for a batch of events of one key (`NervesHub.Integrations.ChannelEvents`)."
  @callback build(key :: String.t(), events :: [map(), ...]) :: map()

  @doc "The body `Send test message` posts."
  @callback test(org_name :: String.t(), user_name :: String.t(), labels :: [String.t()]) :: map()
end
