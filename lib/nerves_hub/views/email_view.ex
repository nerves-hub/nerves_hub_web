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
        #{closing_message()}

        #{signoff()}
    """
  end

  defp closing_message() do
    if email = Application.get_env(:nerves_hub, :support_email_address) do
      """
          <p>If you run into problems, please email <a href="mailto:#{email}">#{email}</a>.</p>
      """
    else
      """
      """
    end
  end

  defp signoff() do
    if signoff = Application.get_env(:nerves_hub, :support_email_signoff) do
      """
          <p>Thanks,</p>

          <p>#{signoff}</p>
      """
    else
      """
      """
    end
  end
end
