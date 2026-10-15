defmodule NervesHubWeb.Integrations.Slack.CommandsController do
  @moduledoc """
  The Slack app's slash command request URL. Requests reach here only once
  `NervesHubWeb.Integrations.Slack.VerifyRequest` has checked Slack signed them, and
  are answered by `NervesHubWeb.Integrations.Slack.Commands`.
  """
  use NervesHubWeb, :controller

  alias NervesHubWeb.Integrations.Slack.Commands

  # The body only: Slack's signature covers the body, not the query string,
  # which `params` would mix in.
  def create(conn, _params) do
    json(conn, Commands.handle(conn.body_params))
  end
end
