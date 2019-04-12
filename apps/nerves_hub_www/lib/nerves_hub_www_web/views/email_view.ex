defmodule NervesHubWWWWeb.EmailView do
  use NervesHubWWWWeb, :view

  def base_url do
    scheme = Application.get_env(:nerves_hub_www, NervesHubWWWWeb.Endpoint)[:url][:scheme]
    scheme = scheme || :https
    host = Application.get_env(:nerves_hub_www, NervesHubWWWWeb.Endpoint)[:url][:host]
    port = Application.get_env(:nerves_hub_www, NervesHubWWWWeb.Endpoint)[:url][:port]
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
        <p>Your frends at NervesHub</p>
    """
  end
end
