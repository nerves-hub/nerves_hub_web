defmodule NervesHubWeb.Presence do
  @moduledoc """
  Provides presence tracking to channels and processes.

  See the [`Phoenix.Presence`](https://hexdocs.pm/phoenix/Phoenix.Presence.html)
  docs for more details.
  """
  use Phoenix.Presence,
    otp_app: :nerves_hub,
    pubsub_server: NervesHub.PubSub

  require Logger

  alias NervesHub.Helpers.Logging

  @impl Phoenix.Presence
  def init(_opts) do
    {:ok, %{}}
  end

  @impl Phoenix.Presence
  def fetch(_topic, presences) do
    for {key, %{metas: [meta | metas]}} <- presences, into: %{} do
      {key, %{metas: [meta | metas], id: key, user: %{name: meta.name}}}
    end
  end

  @impl Phoenix.Presence
  def handle_metas(topic, %{joins: joins, leaves: leaves}, presences, state) do
    for {user_id, presence} <- joins do
      user_data = %{id: user_id, user: presence.user, metas: Map.fetch!(presences, user_id)}
      msg = {__MODULE__, {:join, user_data}}
      Phoenix.PubSub.local_broadcast(NervesHub.PubSub, "proxy:#{topic}", msg)
    end

    for {user_id, presence} <- leaves do
      metas =
        case Map.fetch(presences, user_id) do
          {:ok, presence_metas} -> presence_metas
          :error -> []
        end

      user_data = %{id: user_id, user: presence.user, metas: metas}
      msg = {__MODULE__, {:leave, user_data}}
      Phoenix.PubSub.local_broadcast(NervesHub.PubSub, "proxy:#{topic}", msg)
    end

    {:ok, state}
  end

  @doc """
  Returns a list of present users in a topic.
  """
  @spec list_present_users(String.t()) :: [map()]
  def list_present_users(topic),
    do: list(topic) |> Enum.map(fn {_id, presence} -> presence end)

  @doc """
  Tracks a user's presence in a topic.

  Returns an :ok tuple with reference on success, {:error, reason} on failure.
  """
  @spec track_user(String.t(), String.t(), map()) ::
          {:ok, binary()} | {:error, term()}
  def track_user(topic, id, params) do
    case track(self(), topic, id, params) do
      {:ok, ref} ->
        {:ok, ref}

      {:error, reason} ->
        Logger.error("Failed to track user #{id} in topic #{topic}: #{inspect(reason)}")

        Logging.log_message_to_sentry("Failed to track user #{id} in topic #{topic}", %{
          reason: reason
        })

        {:error, reason}
    end
  end

  @doc """
  Subscribes to presence events for a topic.

  Returns :ok on success, :error on failure.
  """
  @spec subscribe(String.t()) :: :ok | :error
  def subscribe(topic) do
    case Phoenix.PubSub.subscribe(NervesHub.PubSub, "proxy:#{topic}") do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to subscribe to presence topic #{topic}: #{inspect(reason)}")

        Logging.log_message_to_sentry("Failed to subscribe to presence topic #{topic}", %{
          reason: reason
        })

        :error
    end
  end
end
