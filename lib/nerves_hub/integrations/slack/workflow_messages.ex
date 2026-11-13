defmodule NervesHub.Integrations.Slack.WorkflowMessages do
  @moduledoc """
  Keeps the Slack messages with buttons for a deployment workflow step up to
  date once the step is dealt with.

  A message saying a workflow is waiting for approval has an Approve button,
  and one saying a step failed has Retry and Skip. Left alone, those buttons
  would stay long after somebody approved, retried or skipped the step, in
  Slack, on the deployment group's page or through the API, and the channel
  would go on looking as if it were waiting. So each such message is
  recorded as it is posted (`record/4`), what happens to its steps is
  recorded against it (`resolve/2`), and it is rebuilt and edited
  (`chat.update`) to say so in place of the buttons
  (`NervesHub.Workers.UpdateSlackWorkflowMessage`).

  A step can be on more than one message: a channel can get it twice when a
  retried step fails again, and several channels can get the same event. All
  of them are edited. The first thing that happened to a step on a message
  is what that message says: a later retry is told by the message about the
  later failure.

  A message is forgotten once every step it has buttons for was dealt with,
  or when Slack says it is gone. One whose steps are never dealt with is
  forgotten after 30 days, and keeps its buttons; clicking one still
  checks the step first (`NervesHubWeb.Integrations.Slack.WorkflowSteps`).
  """

  import Ecto.Query

  alias NervesHub.Integrations.Slack.Client
  alias NervesHub.Integrations.Slack.Messages
  alias NervesHub.Integrations.Slack.Subscription
  alias NervesHub.Integrations.Slack.WorkflowMessage
  alias NervesHub.Repo
  alias NervesHub.Workers.UpdateSlackWorkflowMessage

  require Logger

  @types ["deployment_group.workflow_step.awaiting_approval", "deployment_group.workflow_step.failed"]

  @max_age_days 30

  # Slack's answers that mean the message cannot be edited, now or later.
  @gone ~w(message_not_found cant_update_message channel_not_found is_archived not_in_channel
           invalid_auth not_authed token_revoked account_inactive)

  @doc "Whether messages of this event key have buttons for steps, and so are recorded."
  @spec recorded_type?(String.t()) :: boolean()
  def recorded_type?(type), do: type in @types

  @doc """
  Records a message just posted to the subscription's channel, from Slack's
  answer to the post (its `channel` and `ts`), if it has buttons for steps.

  Messages older than the longest one is kept are dropped on the way, which
  is all the clearing up they need.
  """
  @spec record(Subscription.t(), String.t(), [map()], map()) :: :ok
  def record(%Subscription{} = subscription, type, events, %{"channel" => channel_id, "ts" => ts})
      when type in @types and is_binary(channel_id) and is_binary(ts) do
    step_ids = for event <- events, id = get_in(event, ["step", "id"]), is_integer(id), uniq: true, do: id

    _ =
      if step_ids != [] do
        Repo.insert!(%WorkflowMessage{
          subscription_id: subscription.id,
          channel_id: channel_id,
          ts: ts,
          type: type,
          events: events,
          step_ids: step_ids
        })
      end

    cutoff = DateTime.add(DateTime.utc_now(), -@max_age_days, :day)
    {_count, _} = WorkflowMessage |> where([m], m.inserted_at < ^cutoff) |> Repo.delete_all()

    :ok
  end

  def record(_subscription, _type, _events, _answer), do: :ok

  @doc """
  Records what happened to the steps on every message with buttons for them,
  and queues each message to be edited.

  `resolution` is `%{"change" => "approved" | "retried" | "skipped", "by" =>
  name}`, or `%{"change" => "replaced", "release" => number}`. A step that
  already has a resolution on a message keeps it.
  """
  @spec resolve([pos_integer()], map()) :: :ok
  def resolve([], _resolution), do: :ok

  def resolve(step_ids, resolution) when is_list(step_ids) do
    new = Map.new(step_ids, &{Integer.to_string(&1), resolution})

    # `new || resolutions`: on keys in both, the one already there wins.
    {_count, message_ids} =
      from(m in WorkflowMessage,
        where: fragment("? && ?", m.step_ids, type(^step_ids, {:array, :integer})),
        update: [set: [resolutions: fragment("?::jsonb || ?", type(^new, :map), m.resolutions)]],
        select: m.id
      )
      |> Repo.update_all([])

    for id <- message_ids do
      {:ok, _job} = Oban.insert(UpdateSlackWorkflowMessage.new(%{workflow_message_id: id}))
    end

    :ok
  end

  @doc "Whether the message in this channel, at this `ts`, is one being kept up to date."
  @spec recorded?(String.t() | nil, String.t() | nil) :: boolean()
  def recorded?(channel_id, ts) when is_binary(channel_id) and is_binary(ts) do
    WorkflowMessage |> where(channel_id: ^channel_id, ts: ^ts) |> Repo.exists?()
  end

  def recorded?(_channel_id, _ts), do: false

  @doc """
  Edits a recorded message to say what happened to its steps. For
  `NervesHub.Workers.UpdateSlackWorkflowMessage`.

  Returns `:ok` once edited, or when there is nothing left to edit;
  `{:rate_limited, seconds}` when Slack asked NervesHub to wait; and
  `{:error, message}` for a failure worth trying again.
  """
  @spec update(pos_integer()) :: :ok | {:rate_limited, pos_integer()} | {:error, String.t()}
  def update(id) do
    WorkflowMessage
    |> preload(subscription: [connection: :workspace])
    |> Repo.get(id)
    |> case do
      nil -> :ok
      message -> edit(message)
    end
  end

  defp edit(%WorkflowMessage{subscription: subscription} = message) do
    built = Messages.build(message.type, message.events, message.resolutions)

    case Client.update_message(subscription.connection.workspace.bot_token, message.channel_id, message.ts, built) do
      {:ok, _} ->
        if settled?(message), do: _ = Repo.delete(message, allow_stale: true)
        :ok

      {:error, {:rate_limited, seconds}} ->
        {:rate_limited, seconds}

      {:error, error} when error in @gone ->
        Logger.info("Forgetting a Slack workflow message that can no longer be edited: #{error}")
        _ = Repo.delete(message, allow_stale: true)
        :ok

      {:error, error} ->
        {:error, error}
    end
  end

  defp settled?(%WorkflowMessage{step_ids: step_ids, resolutions: resolutions}) do
    Enum.all?(step_ids, &Map.has_key?(resolutions, Integer.to_string(&1)))
  end
end
