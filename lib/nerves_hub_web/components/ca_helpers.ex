defmodule NervesHubWeb.Components.CAHelpers do
  use NervesHubWeb, :component

  def check_expiration_tooltip(assigns) do
    ~H"""
    <span class="tooltip-info"></span>
    <span class="tooltip-text">
      By default, the time validity of CA certificates is unchecked. You can
      toggle this to check expiration to prevent device certificates
      from being created from an expired signing CA certificate.
    </span>
    """
  end

  def certificate_status(assigns) do
    status =
      cond do
        DateTime.after?(DateTime.utc_now(), assigns.not_after) ->
          "Expired"

        DateTime.after?(DateTime.shift(DateTime.utc_now(), month: -3), assigns.not_after) ->
          "Expiring Soon"

        true ->
          "Current"
      end

    assigns = %{
      status: status,
      class: certificate_status_class(status)
    }

    ~H"""
    <div class={@class}>
      {@status}
    </div>
    """
  end

  defp certificate_status_class(status) do
    formatted =
      status
      |> String.downcase()
      |> String.replace(" ", "-")

    "certificate-status-#{formatted}"
  end
end
