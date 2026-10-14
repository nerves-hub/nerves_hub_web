defmodule NervesHubWeb.Integrations.Slack.EventsController do
  @moduledoc """
  The Slack app's Events API request URL. Requests reach here only once
  `NervesHubWeb.Integrations.Slack.VerifyRequest` has checked Slack signed them.

  Slack expects an answer within three seconds and retries otherwise, so
  every event is answered with a 200, including the ones NervesHub ignores.
  Links posted to this instance (`link_shared`) are previewed by
  `NervesHubWeb.Integrations.Slack.Unfurls`, in the background.
  """
  use NervesHubWeb, :controller

  alias NervesHub.Integrations.Slack
  alias NervesHubWeb.Integrations.Slack.Unfurls

  # The body only: Slack's signature covers the body, not the query string,
  # which `params` would mix in.
  def create(conn, _params), do: handle(conn, conn.body_params)

  # Sent once, when the request URL is saved in the app's settings.
  defp handle(conn, %{"type" => "url_verification", "challenge" => challenge}) when is_binary(challenge) do
    json(conn, %{challenge: challenge})
  end

  # Previewing a link looks things up and calls Slack back, which can take
  # longer than Slack waits for an answer.
  defp handle(conn, %{"type" => "event_callback", "team_id" => team_id, "event" => %{"type" => "link_shared"} = event})
       when is_binary(team_id) do
    {:ok, _pid} = Task.Supervisor.start_child(NervesHub.TaskSupervisor, fn -> Unfurls.unfurl(team_id, event) end)

    send_resp(conn, 200, "")
  end

  defp handle(conn, %{"type" => "event_callback", "team_id" => team_id, "event" => event})
       when is_binary(team_id) and is_map(event) do
    :ok = Slack.handle_event(team_id, event)

    send_resp(conn, 200, "")
  end

  defp handle(conn, _body), do: send_resp(conn, 200, "")
end
