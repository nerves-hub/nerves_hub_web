defmodule NervesHubWebCore.EmailView do
  use Phoenix.View,
    root: "lib/nerves_hub_web_core/templates",
    namespace: NervesHubWebCore

  import Phoenix.HTML

  def base_url do
    scheme = Application.get_env(:nerves_hub_web_core, :scheme, :https)
    host = Application.get_env(:nerves_hub_web_core, :host)
    port = Application.get_env(:nerves_hub_web_core, :port)
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
