defmodule NervesHub.EmailView do
  use Phoenix.View,
    root: "lib/nerves_hub/templates",
    namespace: NervesHub

  import Phoenix.HTML

  def base_url do
    config = Application.get_env(:nerves_hub, NervesHubWeb.Endpoint)

    port =
      case Enum.member?([443, 80], config[:url][:port]) do
        true -> ""
        _ -> ":#{config[:url][:port]}"
      end

    "#{config[:url][:scheme]}://#{config[:url][:host]}#{port}"
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
