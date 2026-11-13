defmodule NervesHubWeb.Integrations.Slack.EventCallbacks do
  @moduledoc """
  What NervesHub does with an event Slack sends (an Events API
  `event_callback`), however it arrived: posted to the events URL
  (`NervesHubWeb.Integrations.Slack.EventsController`) or down a Socket Mode
  connection (`NervesHubWeb.Integrations.Slack.Socket`).

  A link posted to this instance (`link_shared`) is previewed by
  `NervesHubWeb.Integrations.Slack.Unfurls` in the background, since that
  looks things up and calls Slack back. Everything else is handled by
  `NervesHub.Integrations.Slack.handle_event/2`, and what NervesHub has no
  use for is ignored.
  """

  alias NervesHub.Integrations.Slack
  alias NervesHubWeb.Integrations.Slack.Unfurls

  @doc "Handles an event callback's body, as Slack sent it."
  @spec handle(map()) :: :ok
  def handle(%{"type" => "event_callback", "team_id" => team_id, "event" => %{"type" => "link_shared"} = event})
      when is_binary(team_id) do
    {:ok, _pid} = Task.Supervisor.start_child(NervesHub.TaskSupervisor, fn -> Unfurls.unfurl(team_id, event) end)
    :ok
  end

  def handle(%{"type" => "event_callback", "team_id" => team_id, "event" => event})
      when is_binary(team_id) and is_map(event) do
    Slack.handle_event(team_id, event)
  end

  def handle(_body), do: :ok
end
