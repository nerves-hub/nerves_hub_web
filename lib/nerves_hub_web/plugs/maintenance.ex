defmodule NervesHubWeb.Plugs.Maintenance do
  @moduledoc """
  Answers every request with a 503: the maintenance page for people, and the API's
  error shape for the API and for anything else that asks for JSON.
  """

  @behaviour Plug

  import Plug.Conn

  alias NervesHubWeb.MaintenanceHTML
  alias Phoenix.HTML.Safe

  # Seconds. Only a hint, for the clients that read it and the crawlers that would
  # otherwise treat the 503 as the site having gone.
  @retry_after "300"

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    platform_name = Application.get_env(:nerves_hub, :friendly_platform_name)
    status_page_url = Application.get_env(:nerves_hub, :status_page_url)

    conn = put_resp_header(conn, "retry-after", @retry_after)

    conn =
      if wants_json?(conn) do
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(503, Jason.encode!(%{errors: %{detail: json_detail(platform_name, status_page_url)}}))
      else
        body =
          %{
            platform_name: platform_name,
            page_title: Application.get_env(:nerves_hub, :web_title_suffix),
            status_page_url: status_page_url
          }
          |> MaintenanceHTML.page()
          |> Safe.to_iodata()

        conn
        |> put_resp_content_type("text/html")
        |> send_resp(503, body)
      end

    halt(conn)
  end

  defp wants_json?(%{path_info: ["api" | _]}), do: true

  defp wants_json?(conn) do
    conn
    |> get_req_header("accept")
    |> Enum.any?(&String.contains?(&1, "json"))
  end

  defp json_detail(platform_name, nil), do: "#{platform_name} is offline for planned maintenance."

  defp json_detail(platform_name, status_page_url) do
    "#{json_detail(platform_name, nil)} See #{status_page_url} for progress."
  end
end
