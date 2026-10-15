defmodule NervesHubWeb.Integrations.Slack.EventsController do
  @moduledoc """
  The Slack app's Events API request URL. Requests reach here only once
  `NervesHubWeb.Integrations.Slack.VerifyRequest` has checked Slack signed them.

  Slack expects an answer within three seconds and retries otherwise, so
  every event is answered with a 200, including the ones NervesHub ignores.
  What is done with each is `NervesHubWeb.Integrations.Slack.EventCallbacks`,
  shared with Socket Mode.
  """
  use NervesHubWeb, :controller

  alias NervesHubWeb.Integrations.Slack.EventCallbacks

  # The body only: Slack's signature covers the body, not the query string,
  # which `params` would mix in.
  def create(conn, _params), do: handle(conn, conn.body_params)

  # Sent once, when the request URL is saved in the app's settings.
  defp handle(conn, %{"type" => "url_verification", "challenge" => challenge}) when is_binary(challenge) do
    json(conn, %{challenge: challenge})
  end

  defp handle(conn, body) do
    :ok = EventCallbacks.handle(body)
    send_resp(conn, 200, "")
  end
end
