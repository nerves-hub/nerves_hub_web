defmodule NervesHubWeb.Integrations.Slack.InteractionsController do
  @moduledoc """
  The Slack app's interactivity request URL, which Slack calls when someone
  clicks a button on one of NervesHub's messages. Requests reach here only
  once `NervesHubWeb.Integrations.Slack.VerifyRequest` has checked Slack signed them.

  Slack sends the interaction as a JSON `payload` form field, and wants an
  answer within three seconds, so the click is handed to
  `NervesHubWeb.Integrations.Slack.Actions` to carry out in the background and answered at
  once.
  """
  use NervesHubWeb, :controller

  alias NervesHubWeb.Integrations.Slack.Actions

  # The body only: Slack's signature covers the body, not the query string,
  # which `params` would mix in.
  def create(%{body_params: %{"payload" => payload}} = conn, _params) when is_binary(payload) do
    case Jason.decode(payload) do
      {:ok, %{} = interaction} ->
        :ok = Actions.handle_interaction(interaction)
        send_resp(conn, 200, "")

      _ ->
        send_resp(conn, 400, "")
    end
  end

  def create(conn, _params), do: send_resp(conn, 400, "")
end
