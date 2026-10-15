defmodule NervesHub.Integrations.Teams do
  @moduledoc """
  The Microsoft Teams channels an organization's device events are posted
  to, each through a Workflows webhook somebody made in the channel
  (`NervesHub.Integrations.Teams.Channel`).

  Teams retired its incoming webhooks (Office 365 connectors) in May 2026.
  A Workflows webhook is their replacement: a Power Automate flow, made from
  the channel, that posts the Adaptive Cards it is sent. It needs no app
  installed and nothing configured on the instance, but nothing comes back
  from it either: a card cannot have buttons that act, and a card once posted
  cannot be changed.

  A channel hears every product or the products it lists, and names the
  events it wants (`NervesHub.Integrations.ChannelEvents`), as a Slack
  channel does.

  ## How events reach a channel

  `NervesHub.Integrations.dispatch/3` hands an event to `queue_events/3` for
  the channels that want it. Each is written to `teams_pending_events`, and
  the channel gets one `NervesHub.Workers.PostTeamsEvents` job, 15 seconds
  out, however many events arrive meanwhile. That job posts everything held
  for the channel as one card per kind of event
  (`NervesHub.Integrations.Teams.Cards`), which keeps a fleet changing at
  once from burying the channel, and Power Automate from throttling it.

  A webhook Teams refuses (its workflow was deleted or turned off) turns the
  channel off, and each product it heard gets a notification saying so.
  """

  import Ecto.Query

  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.Scope
  alias NervesHub.AuditLogs.OrgTemplates
  alias NervesHub.Integrations
  alias NervesHub.Integrations.ChannelEvents
  alias NervesHub.Integrations.ProductScope
  alias NervesHub.Integrations.Teams.Cards
  alias NervesHub.Integrations.Teams.Channel
  alias NervesHub.Integrations.Teams.Client
  alias NervesHub.Integrations.Teams.PendingEvent
  alias NervesHub.ProductNotifications
  alias NervesHub.Repo
  alias NervesHub.Workers.PostTeamsEvents

  require Logger

  @max_channels_per_org 20

  # How long events are held before posting, so a burst becomes one card.
  @batch_seconds 15

  # The most events one job posts. A larger backlog is posted by the jobs
  # that follow, so one channel's flood cannot hold a worker for long.
  @max_batch 500

  # Events still waiting after this are dropped rather than posted late: an
  # hour-old "unhealthy" is noise, and a channel that was failing for a while
  # should not be flooded once it recovers.
  @max_age_seconds 3600

  @doc "How many Teams channels an organization may send events to."
  def max_channels_per_org(), do: @max_channels_per_org

  @doc "The organization's Teams channels, oldest first, with their products."
  @spec list_channels(Org.t()) :: [Channel.t()]
  def list_channels(%Org{id: org_id}) do
    Channel
    |> where(org_id: ^org_id)
    |> order_by(asc: :inserted_at, asc: :id)
    |> preload(:products)
    |> Repo.all()
  end

  @doc "One of the organization's channels. Raises if it has none with that id."
  @spec get_channel!(Org.t(), pos_integer() | String.t()) :: Channel.t()
  def get_channel!(%Org{id: org_id}, id) do
    Channel
    |> where(id: ^id, org_id: ^org_id)
    |> preload(:products)
    |> Repo.one!()
  end

  @doc "A changeset for the channel form. `attrs` names products by name."
  @spec change_channel(Org.t(), Channel.t(), map()) :: Ecto.Changeset.t()
  def change_channel(%Org{} = org, %Channel{} = channel, attrs \\ %{}) do
    attrs = ProductScope.normalize_attrs(attrs)

    case channel do
      %Channel{id: nil} -> Channel.create_changeset(org, attrs, ProductScope.find_products(org, attrs))
      channel -> Channel.changeset(channel, attrs, ProductScope.find_products(org, attrs))
    end
  end

  @doc """
  Starts posting the events `attrs` names to the channel behind a Workflows
  webhook (`"url"`), from every product or the products it names.

  Returns `{:error, :too_many_channels}` when the organization already has
  `max_channels_per_org/0`.
  """
  @spec create_channel(Scope.t(), map()) :: {:ok, Channel.t()} | {:error, Ecto.Changeset.t() | :too_many_channels}
  def create_channel(%Scope{org: %Org{} = org, user: user}, attrs) do
    attrs = ProductScope.normalize_attrs(attrs)

    Repo.transact(fn ->
      with true <- count(org) < @max_channels_per_org || {:error, :too_many_channels},
           {:ok, channel} <-
             org
             |> Channel.create_changeset(attrs, ProductScope.find_products(org, attrs))
             |> Repo.insert() do
        :ok = OrgTemplates.audit_teams_channel_created(user, org, channel)
        {:ok, channel}
      end
    end)
    |> tap(&invalidate_on_success(&1, org))
  end

  defp count(%Org{id: org_id}), do: Channel |> where(org_id: ^org_id) |> Repo.aggregate(:count)

  @doc """
  Changes a channel's name, events, products, or whether it is on, and its
  webhook URL when `attrs` gives a new one.
  """
  @spec update_channel(Scope.t(), Channel.t(), map()) :: {:ok, Channel.t()} | {:error, Ecto.Changeset.t()}
  def update_channel(%Scope{org: org, user: user}, %Channel{} = channel, attrs) do
    attrs = ProductScope.normalize_attrs(attrs)

    Repo.transact(fn ->
      changeset =
        channel
        |> Repo.preload(:products)
        |> Channel.changeset(attrs, ProductScope.find_products(org, attrs))

      with {:ok, updated} <- Repo.update(changeset) do
        :ok = OrgTemplates.audit_teams_channel_updated(user, org, updated, Ecto.Changeset.changed?(changeset, :url))
        {:ok, updated}
      end
    end)
    |> tap(&invalidate_on_success(&1, org))
  end

  @doc "Stops posting to the channel. Events held for it are dropped."
  @spec delete_channel(Scope.t(), Channel.t()) :: {:ok, Channel.t()} | {:error, Ecto.Changeset.t()}
  def delete_channel(%Scope{org: org, user: user}, %Channel{} = channel) do
    Repo.transact(fn ->
      with {:ok, deleted} <- Repo.delete(channel) do
        :ok = OrgTemplates.audit_teams_channel_deleted(user, org, deleted)
        {:ok, deleted}
      end
    end)
    |> tap(&invalidate_on_success(&1, org))
  end

  @doc """
  Posts a card to the channel straight away saying what it will be sent,
  whether or not the channel is on, and returns how Teams answered.
  Recorded nowhere, like a webhook's test event.
  """
  @spec send_test_message(Scope.t(), Channel.t()) :: :ok | {:error, Client.error()}
  def send_test_message(%Scope{org: org, user: user}, %Channel{} = channel) do
    labels = Enum.map(channel.events, &ChannelEvents.label/1)
    Client.post(channel.url, Cards.test(org.name, user.name, labels))
  end

  @doc """
  Holds an event, already cleaned by `NervesHub.Integrations.dispatch/3`, for
  each of `channel_ids` that wants it, and makes sure each has a job coming
  to post it.

  Which channels want it is decided here, not by the dispatcher, because
  some depend on the event's data: a finished update is wanted by the
  channels for failures or for successes, depending on its outcome.
  """
  @spec queue_events([pos_integer()], String.t(), map()) :: :ok
  def queue_events(channel_ids, type, data) do
    case ChannelEvents.key(type, data) do
      nil -> :ok
      key -> hold(key, data, wanting(channel_ids, key))
    end
  end

  defp hold(_key, _data, []), do: :ok

  defp hold(key, data, wanting) do
    now = DateTime.utc_now()

    {_count, _} =
      Repo.insert_all(PendingEvent, Enum.map(wanting, &%{channel_id: &1, type: key, data: data, inserted_at: now}))

    for id <- wanting do
      {:ok, _job} = Oban.insert(PostTeamsEvents.new(%{channel_id: id}, schedule_in: @batch_seconds))
    end

    :ok
  end

  defp wanting(channel_ids, key) do
    Channel
    |> where([c], c.id in ^channel_ids and c.enabled and ^key in c.events)
    |> select([c], c.id)
    |> Repo.all()
  end

  @doc """
  Posts what is held for the channel. For `NervesHub.Workers.PostTeamsEvents`.

  Returns `:ok` once everything held was posted, `{:rate_limited, seconds}`
  when Power Automate asked NervesHub to wait, `{:cancel, reason}` when the
  channel is gone or was turned off (here, when Teams refused the webhook),
  and `{:error, message}` for a failure worth trying again.
  """
  @spec post_pending_events(pos_integer()) ::
          :ok | {:rate_limited, pos_integer()} | {:cancel, String.t()} | {:error, String.t()}
  def post_pending_events(channel_id) do
    case deliverable_channel(channel_id) do
      nil ->
        :ok = drop_pending(channel_id)
        {:cancel, "the channel was deleted or turned off"}

      channel ->
        :ok = drop_stale(channel.id)

        PendingEvent
        |> where(channel_id: ^channel.id)
        |> order_by(:id)
        |> limit(@max_batch)
        |> Repo.all()
        |> post_batch(channel)
    end
  end

  defp deliverable_channel(id) do
    Channel
    |> join(:inner, [c], o in Org, on: o.id == c.org_id)
    |> where([c, o], c.id == ^id and c.enabled and is_nil(o.deleted_at))
    |> Repo.one()
  end

  defp post_batch([], _channel), do: :ok

  # One card per kind of event, posted in the order each kind first
  # happened, as Slack's messages are.
  defp post_batch(events, channel) do
    events
    |> Enum.group_by(& &1.type)
    |> Enum.sort_by(fn {_key, [first | _]} -> first.id end)
    |> Enum.reduce_while(:ok, fn {key, group}, :ok ->
      case Client.post(channel.url, Cards.build(key, Enum.map(group, & &1.data))) do
        :ok ->
          :ok = delete_events(group)
          {:cont, :ok}

        {:error, error} ->
          {:halt, failed(channel, error)}
      end
    end)
    |> case do
      :ok ->
        :ok = clear_error(channel)
        :ok = continue_backlog(channel, length(events))

      failure ->
        failure
    end
  end

  # A full batch means more may be waiting. The next job is queued now rather
  # than left for the next event, which may be a while coming.
  defp continue_backlog(channel, @max_batch) do
    {:ok, _job} = Oban.insert(PostTeamsEvents.new(%{channel_id: channel.id}))
    :ok
  end

  defp continue_backlog(_channel, _posted), do: :ok

  defp failed(_channel, {:rate_limited, seconds}), do: {:rate_limited, seconds}

  defp failed(channel, {:refused, reason}) do
    :ok = disable(channel, reason)
    {:cancel, "turned off because #{reason}"}
  end

  defp failed(channel, error) when is_binary(error) do
    :ok = record_error(channel, error)
    {:error, error}
  end

  defp delete_events(events) do
    ids = Enum.map(events, & &1.id)
    {_count, _} = PendingEvent |> where([e], e.id in ^ids) |> Repo.delete_all()
    :ok
  end

  defp drop_pending(channel_id) do
    {_count, _} = PendingEvent |> where(channel_id: ^channel_id) |> Repo.delete_all()
    :ok
  end

  defp drop_stale(channel_id) do
    cutoff = DateTime.add(DateTime.utc_now(), -@max_age_seconds)

    {count, _} =
      PendingEvent
      |> where([e], e.channel_id == ^channel_id and e.inserted_at < ^cutoff)
      |> Repo.delete_all()

    if count > 0 do
      Logger.info("Dropped #{count} Teams events held more than an hour for channel #{channel_id}")
    end

    :ok
  end

  defp record_error(%Channel{id: id}, error) do
    {_count, _} =
      Channel
      |> where(id: ^id)
      |> Repo.update_all(set: [last_error: String.slice(error, 0, 500), last_error_at: DateTime.utc_now(:second)])

    :ok
  end

  defp clear_error(%Channel{last_error: nil}), do: :ok

  defp clear_error(%Channel{id: id}) do
    {_count, _} = Channel |> where(id: ^id) |> Repo.update_all(set: [last_error: nil, last_error_at: nil])
    :ok
  end

  defp disable(%Channel{id: id} = channel, reason) do
    {count, _} =
      Channel
      |> where([c], c.id == ^id and c.enabled)
      |> Repo.update_all(set: [enabled: false, disabled_reason: "Turned off because #{reason}."])

    :ok = drop_pending(id)

    # Only the job that turned it off says so.
    _ =
      if count == 1 do
        :ok = Integrations.invalidate(channel.org_id)

        product_ids =
          ProductScope.heard_product_ids(
            channel.org_id,
            channel.all_products,
            "teams_channel_products",
            :channel_id,
            id
          )

        _ = ProductNotifications.create_teams_channel_disabled_notifications!(channel, product_ids, reason)
      end

    :ok
  end

  defp invalidate_on_success({:ok, _channel}, %Org{id: org_id}), do: Integrations.invalidate(org_id)
  defp invalidate_on_success(_error, _org), do: :ok
end
