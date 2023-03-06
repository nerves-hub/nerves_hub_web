defmodule NervesHub.EmailView do
  use Phoenix.View,
    root: "lib/nerves_hub/templates",
    namespace: NervesHub

  import Phoenix.HTML

  alias NervesHub.Config

  def base_url do
    vapor_config = Vapor.load!(Config)
    endpoint_config = vapor_config.web_endpoint

    scheme = endpoint_config.url_scheme
    host = endpoint_config.url_host
    port = endpoint_config.url_port
    port = if Enum.member?([443, 80], port), do: "", else: ":#{port}"

    "#{scheme}://#{host}#{port}"
  end

  @doc """
  Standard closing words.
  """

  def closing do
    """
        <p>If you run into problems, please file an <a href="https://github.com/nerves-hub/nerves_hub_web/issues">issue</a> or email support@nerves-hub.org.</p>
        <p>Thanks,</p>
        <p>Your friends at NervesHub</p>
    """
  end
end
