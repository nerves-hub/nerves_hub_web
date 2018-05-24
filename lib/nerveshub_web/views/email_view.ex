defmodule NervesHubWeb.EmailView do
  use NervesHubWeb, :view

  def base_url do
    scheme = Application.get_env(:nerveshub, NervesHubWeb.Endpoint)[:url][:scheme]
    host = Application.get_env(:nerveshub, NervesHubWeb.Endpoint)[:url][:host]
    port = Application.get_env(:nerveshub, NervesHubWeb.Endpoint)[:url][:port]
    port = if Enum.member?([443, 80], port), do: "", else: ":#{port}"

    "#{scheme}://#{host}#{port}"
  end
end
