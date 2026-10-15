defmodule NervesHubWeb.Integrations.Slack.EventsController do
  @moduledoc """
  The Slack app's Events API request URL. Requests reach here only once
  `NervesHubWeb.Integrations.Slack.VerifyRequest` has checked Slack signed them.

  Slack expects an answer within three seconds and retries otherwise, so
  every event is answered with a 200, including the ones NervesHub ignores.
  """
  use NervesHubWeb, :controller

  alias NervesHub.Integrations.Slack

  # Sent once, when the request URL is saved in the app's settings.
  def create(conn, %{"type" => "url_verification", "challenge" => challenge}) when is_binary(challenge) do
    json(conn, %{challenge: challenge})
  end

  def create(conn, %{"type" => "event_callback", "team_id" => team_id, "event" => event})
      when is_binary(team_id) and is_map(event) do
    :ok = Slack.handle_event(team_id, event)

    send_resp(conn, 200, "")
  end

  def create(conn, _params), do: send_resp(conn, 200, "")
end
