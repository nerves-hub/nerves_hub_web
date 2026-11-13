defmodule NervesHub.Integrations.Slack.Subscriptions do
  @moduledoc """
  The Slack channels an organization's device events are posted to.

  A subscription belongs to one of the organization's workspace connections
  (`NervesHub.Integrations.Slack.Connection`), hears every product or the products it
  lists, and names the events it wants (`NervesHub.Integrations.ChannelEvents`).

  ## How events reach a channel

  `NervesHub.Integrations.dispatch/3` hands an event to `queue_events/3` for
  the subscriptions that want it. Each is written to `slack_pending_events`,
  and the subscription gets one `NervesHub.Workers.PostSlackEvents` job,
  15 seconds out, however many events arrive meanwhile. That job posts
  everything held for the channel as one message per kind of event
  (`NervesHub.Integrations.Slack.Messages`), which keeps a fleet that changes at once from
  burying the channel, and keeps NervesHub inside Slack's limit of about one
  message a second per channel.

  An event can be left with no job coming for it, and
  `NervesHub.Workers.QueueStrandedChatEvents` queues one (`queue_stranded/0`).

  A channel that cannot be posted to (archived, deleted, or the app was
  removed from it) turns its subscription off, and each product it heard gets
  a notification saying so.
  """

  import Ecto.Query

  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.Scope
  alias NervesHub.AuditLogs.OrgTemplates
  alias NervesHub.Integrations
  alias NervesHub.Integrations.ChannelEvents
  alias NervesHub.Integrations.ProductScope
  alias NervesHub.Integrations.Slack.Client
  alias NervesHub.Integrations.Slack.Connection
  alias NervesHub.Integrations.Slack.Messages
  alias NervesHub.Integrations.Slack.PendingEvent
  alias NervesHub.Integrations.Slack.Subscription
  alias NervesHub.Integrations.Slack.WorkflowMessages
  alias NervesHub.ProductNotifications
  alias NervesHub.Repo
  alias NervesHub.Workers.PostSlackEvents

  require Logger

  @max_subscriptions_per_org 20

  # How long events are held before posting, so a burst becomes one message.
  @batch_seconds 15

  # Held this long, an event should have been posted: the job that posts it
  # runs 15 seconds after the first event it holds.
  @stranded_seconds @batch_seconds * 2

  # The most events one job posts. A larger backlog is posted by the jobs
  # that follow, so one channel's flood cannot hold a worker for long.
  @max_batch 500

  # Events still waiting after this are dropped rather than posted late: an
  # hour-old "unhealthy" is noise, and a channel that was failing for a while
  # should not be flooded once it recovers.
  @max_age_seconds 3600

  # Slack's answers that mean this channel cannot be posted to until a person
  # does something about it.
  @channel_errors %{
    "channel_not_found" => "the channel no longer exists, or the app cannot see it",
    "is_archived" => "the channel was archived",
    "not_in_channel" => "the app is not in the channel; invite it, then turn this back on",
    "restricted_action" => "the workspace does not let the app post in the channel",
    "invalid_auth" => "Slack refused the workspace's token",
    "not_authed" => "Slack refused the workspace's token",
    "token_revoked" => "the workspace's token was revoked",
    "account_inactive" => "the workspace's token was revoked"
  }

  @doc "How many Slack channels an organization may send events to."
  def max_subscriptions_per_org(), do: @max_subscriptions_per_org

  @doc "One of the organization's subscriptions, with its products and workspace."
  @spec get_subscription!(Org.t(), pos_integer() | String.t()) :: Subscription.t()
  def get_subscription!(%Org{id: org_id}, id) do
    Subscription
    |> join(:inner, [s], c in assoc(s, :connection))
    |> where([s, c], s.id == ^id and c.org_id == ^org_id)
    |> preload([:products, connection: :workspace])
    |> Repo.one!()
  end

  @doc "A changeset for the subscription form. `attrs` names products by name."
  @spec change_subscription(Org.t(), Subscription.t(), map()) :: Ecto.Changeset.t()
  def change_subscription(%Org{} = org, %Subscription{} = subscription, attrs \\ %{}) do
    attrs = ProductScope.normalize_attrs(attrs)
    Subscription.changeset(subscription, attrs, ProductScope.find_products(org, attrs))
  end

  @doc """
  The channels of the connection's workspace the app can post to: every
  public channel, and the private ones it was invited to.
  """
  @spec list_channels(Connection.t()) :: {:ok, [Client.channel()]} | {:error, Client.error()}
  def list_channels(%Connection{} = connection) do
    connection = Repo.preload(connection, :workspace)
    Client.list_channels(connection.workspace.bot_token)
  end

  @doc """
  Starts posting the events `attrs` names to a channel of the connection's
  workspace (`"channel_id"` and `"channel_name"`), from every product or the
  products it names, as a webhook does.

  Returns `{:error, :too_many_subscriptions}` when the organization already
  has `max_subscriptions_per_org/0`.
  """
  @spec create_subscription(Scope.t(), Connection.t(), map()) ::
          {:ok, Subscription.t()} | {:error, Ecto.Changeset.t() | :too_many_subscriptions}
  def create_subscription(
        %Scope{org: %Org{id: org_id} = org, user: user},
        %Connection{org_id: org_id} = connection,
        attrs
      ) do
    attrs = ProductScope.normalize_attrs(attrs)

    Repo.transact(fn ->
      with true <- count(org) < @max_subscriptions_per_org || {:error, :too_many_subscriptions},
           {:ok, subscription} <-
             connection
             |> Subscription.create_changeset(attrs, ProductScope.find_products(org, attrs))
             |> Repo.insert() do
        :ok = OrgTemplates.audit_slack_subscription_created(user, org, subscription)
        {:ok, subscription}
      end
    end)
    |> tap(&invalidate_on_success(&1, org))
  end

  defp count(%Org{id: org_id}) do
    Subscription
    |> join(:inner, [s], c in assoc(s, :connection))
    |> where([_s, c], c.org_id == ^org_id)
    |> Repo.aggregate(:count)
  end

  @doc "Changes a subscription's events, products, or whether it is on."
  @spec update_subscription(Scope.t(), Subscription.t(), map()) ::
          {:ok, Subscription.t()} | {:error, Ecto.Changeset.t()}
  def update_subscription(%Scope{org: org, user: user}, %Subscription{} = subscription, attrs) do
    attrs = ProductScope.normalize_attrs(attrs)

    Repo.transact(fn ->
      changeset =
        subscription
        |> Repo.preload(:products)
        |> Subscription.changeset(attrs, ProductScope.find_products(org, attrs))

      with {:ok, updated} <- Repo.update(changeset) do
        :ok = OrgTemplates.audit_slack_subscription_updated(user, org, updated)
        {:ok, updated}
      end
    end)
    |> tap(&invalidate_on_success(&1, org))
  end

  @doc "Stops posting to the channel. Events held for it are dropped."
  @spec delete_subscription(Scope.t(), Subscription.t()) :: {:ok, Subscription.t()} | {:error, Ecto.Changeset.t()}
  def delete_subscription(%Scope{org: org, user: user}, %Subscription{} = subscription) do
    Repo.transact(fn ->
      with {:ok, deleted} <- Repo.delete(subscription) do
        :ok = OrgTemplates.audit_slack_subscription_deleted(user, org, deleted)
        {:ok, deleted}
      end
    end)
    |> tap(&invalidate_on_success(&1, org))
  end

  @doc """
  Posts a message to the channel straight away saying what it will be sent,
  whether or not the subscription is on, and returns how Slack answered.
  Recorded nowhere, like a webhook's test event.
  """
  @spec send_test_message(Scope.t(), Subscription.t()) :: :ok | {:error, Client.error()}
  def send_test_message(%Scope{org: org, user: user}, %Subscription{} = subscription) do
    subscription = Repo.preload(subscription, connection: :workspace)
    labels = Enum.map(subscription.events, &ChannelEvents.label/1)

    case Client.post_message(
           subscription.connection.workspace.bot_token,
           subscription.channel_id,
           Messages.test(org.name, user.name, labels)
         ) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  @doc """
  Holds an event, already cleaned by `NervesHub.Integrations.dispatch/3`, for
  each of `subscription_ids` that wants it, and makes sure each has a job
  coming to post it.

  Which subscriptions want it is decided here, not by the dispatcher, because
  some depend on the event's data: a finished update is wanted by the
  subscriptions for failures or for successes, depending on its outcome.
  """
  @spec queue_events([pos_integer()], String.t(), map()) :: :ok
  def queue_events(subscription_ids, type, data) do
    case ChannelEvents.key(type, data) do
      nil -> :ok
      key -> queue_events(subscription_ids, key, data, wanting(subscription_ids, key))
    end
  end

  defp queue_events(_subscription_ids, _key, _data, []), do: :ok

  defp queue_events(_subscription_ids, key, data, wanting) do
    now = DateTime.utc_now()

    {_count, _} =
      Repo.insert_all(
        PendingEvent,
        Enum.map(wanting, &%{subscription_id: &1, type: key, data: data, inserted_at: now})
      )

    for id <- wanting do
      {:ok, _job} = Oban.insert(PostSlackEvents.new(%{subscription_id: id}, schedule_in: @batch_seconds))
    end

    :ok
  end

  defp wanting(subscription_ids, key) do
    Subscription
    |> where([s], s.id in ^subscription_ids and s.enabled and ^key in s.events)
    |> select([s], s.id)
    |> Repo.all()
  end

  @doc """
  Queues a `NervesHub.Workers.PostSlackEvents` job for each subscription
  holding events that no job is coming for, and returns how many it queued.
  For `NervesHub.Workers.QueueStrandedChatEvents`.

  Events can be left that way. Queued inside a transaction, an event can find
  the subscription's job still waiting and queue nothing, and that job can
  run before the transaction commits, too soon to see the event. A job that
  gave up after its retries leaves what it could not post behind. Either way
  nothing would come until the channel's next event, which, for a quiet
  channel, can be after the events are an hour old and dropped.

  A subscription with a job waiting, running or retrying gets no other: two
  at once would post the same events twice.
  """
  @spec queue_stranded() :: non_neg_integer()
  def queue_stranded() do
    cutoff = DateTime.add(DateTime.utc_now(), -@stranded_seconds)

    queued =
      PendingEvent
      |> where([e], e.inserted_at < ^cutoff)
      |> distinct(true)
      |> select([e], e.subscription_id)
      |> Repo.all()
      |> Enum.count(fn id ->
        {:ok, job} = Oban.insert(PostSlackEvents.new(%{subscription_id: id}, unique: [states: :incomplete]))
        not job.conflict?
      end)

    if queued > 0 do
      Logger.info("Queued jobs for #{queued} Slack subscriptions holding events that none was coming for")
    end

    queued
  end

  @doc """
  Posts what is held for the subscription. For `NervesHub.Workers.PostSlackEvents`.

  Returns `:ok` once everything held was posted, `{:rate_limited, seconds}`
  when Slack asked NervesHub to wait, `{:cancel, reason}` when the
  subscription is gone or was turned off (here, when the channel cannot be
  posted to), and `{:error, message}` for a failure worth trying again.
  """
  @spec post_pending_events(pos_integer()) ::
          :ok | {:rate_limited, pos_integer()} | {:cancel, String.t()} | {:error, String.t()}
  def post_pending_events(subscription_id) do
    case deliverable_subscription(subscription_id) do
      nil ->
        :ok = drop_pending(subscription_id)
        {:cancel, "the subscription was deleted or turned off"}

      subscription ->
        :ok = drop_stale(subscription.id)

        PendingEvent
        |> where(subscription_id: ^subscription.id)
        |> order_by(:id)
        |> limit(@max_batch)
        |> Repo.all()
        |> post_batch(subscription)
    end
  end

  defp deliverable_subscription(id) do
    Subscription
    |> join(:inner, [s], c in assoc(s, :connection))
    |> join(:inner, [_s, c], o in Org, on: o.id == c.org_id)
    |> where([s, _c, o], s.id == ^id and s.enabled and is_nil(o.deleted_at))
    |> preload(connection: :workspace)
    |> Repo.one()
  end

  defp post_batch([], _subscription), do: :ok

  # One message per kind of event, posted in the order each kind first
  # happened: a workflow step completing and the next one starting arrive
  # together, and should read that way round.
  defp post_batch(events, subscription) do
    events
    |> Enum.group_by(& &1.type)
    |> Enum.sort_by(fn {_key, [first | _]} -> first.id end)
    |> Enum.reduce_while(:ok, fn {key, group}, :ok ->
      events = Enum.map(group, & &1.data)
      message = Messages.build(key, events)

      case Client.post_message(subscription.connection.workspace.bot_token, subscription.channel_id, message) do
        {:ok, answer} ->
          :ok = WorkflowMessages.record(subscription, key, events, answer)
          :ok = delete_events(group)
          {:cont, :ok}

        {:error, error} ->
          {:halt, failed(subscription, error)}
      end
    end)
    |> case do
      :ok ->
        :ok = clear_error(subscription)
        :ok = continue_backlog(subscription, length(events))

      failure ->
        failure
    end
  end

  # A full batch means more may be waiting. The next job is queued now rather
  # than left for the next event, which may be a while coming.
  defp continue_backlog(subscription, @max_batch) do
    {:ok, _job} = Oban.insert(PostSlackEvents.new(%{subscription_id: subscription.id}))
    :ok
  end

  defp continue_backlog(_subscription, _posted), do: :ok

  defp failed(_subscription, {:rate_limited, seconds}), do: {:rate_limited, seconds}

  defp failed(subscription, error) when is_map_key(@channel_errors, error) do
    reason = Map.fetch!(@channel_errors, error)
    :ok = disable(subscription, reason)
    {:cancel, "turned off because #{reason}"}
  end

  defp failed(subscription, error) do
    :ok = record_error(subscription, error)
    {:error, error}
  end

  defp delete_events(events) do
    ids = Enum.map(events, & &1.id)
    {_count, _} = PendingEvent |> where([e], e.id in ^ids) |> Repo.delete_all()
    :ok
  end

  defp drop_pending(subscription_id) do
    {_count, _} = PendingEvent |> where(subscription_id: ^subscription_id) |> Repo.delete_all()
    :ok
  end

  defp drop_stale(subscription_id) do
    cutoff = DateTime.add(DateTime.utc_now(), -@max_age_seconds)

    {count, _} =
      PendingEvent
      |> where([e], e.subscription_id == ^subscription_id and e.inserted_at < ^cutoff)
      |> Repo.delete_all()

    if count > 0 do
      Logger.info("Dropped #{count} Slack events held more than an hour for subscription #{subscription_id}")
    end

    :ok
  end

  defp record_error(%Subscription{id: id}, error) do
    {_count, _} =
      Subscription
      |> where(id: ^id)
      |> Repo.update_all(set: [last_error: String.slice(error, 0, 500), last_error_at: DateTime.utc_now(:second)])

    :ok
  end

  defp clear_error(%Subscription{last_error: nil}), do: :ok

  defp clear_error(%Subscription{id: id}) do
    {_count, _} = Subscription |> where(id: ^id) |> Repo.update_all(set: [last_error: nil, last_error_at: nil])
    :ok
  end

  defp disable(%Subscription{id: id} = subscription, reason) do
    {count, _} =
      Subscription
      |> where([s], s.id == ^id and s.enabled)
      |> Repo.update_all(set: [enabled: false, disabled_reason: "Turned off because #{reason}."])

    :ok = drop_pending(id)

    # Only the job that turned it off says so.
    _ =
      if count == 1 do
        %Connection{org_id: org_id} = subscription.connection
        :ok = Integrations.invalidate(org_id)

        product_ids =
          ProductScope.heard_product_ids(
            org_id,
            subscription.all_products,
            "slack_subscription_products",
            :subscription_id,
            id
          )

        _ = ProductNotifications.create_slack_subscription_disabled_notifications!(subscription, product_ids, reason)
      end

    :ok
  end

  defp invalidate_on_success({:ok, _subscription}, %Org{id: org_id}), do: Integrations.invalidate(org_id)
  defp invalidate_on_success(_error, _org), do: :ok
end
