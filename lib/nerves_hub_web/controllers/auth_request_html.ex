defmodule NervesHubWeb.AuthRequestHTML do
  @moduledoc """
  Pages rendered by `NervesHubWeb.AuthRequestController`.
  """
  use NervesHubWeb, :html

  embed_templates("auth_request_html/*")

  defp format_body(body), do: Jason.encode!(body, pretty: true)

  defp expires_in_minutes(expires_at) do
    expires_at
    |> DateTime.diff(DateTime.utc_now(), :second)
    |> max(0)
    |> div(60)
    |> max(1)
  end
end
