defmodule NervesHubWeb.Components.CAHelpers do
  use NervesHubWeb, :component

  alias NervesHub.Devices.CACertificate
  alias NervesHubWeb.Components.Utils

  @doc """
  How to refer to a CA in a sentence: its description, or its formatted serial
  when it has none (the description is optional).
  """
  @spec label(CACertificate.t()) :: String.t()
  def label(%CACertificate{description: description, serial: serial}) do
    if description in [nil, ""], do: Utils.format_serial(serial), else: description
  end

  attr(:id, :string, default: "check-expiration-tooltip")
  attr(:placement, :string, default: "right")

  def check_expiration_tooltip(assigns) do
    ~H"""
    <.tooltip id={@id} placement={@placement} class="z-20 flex items-center" content_class="w-max max-w-72">
      <.icon name="info" class="text-content-muted" />
      <:content>
        By default, the time validity of CA certificates is unchecked. You can
        toggle this to check expiration to prevent device certificates
        from being created from an expired signing CA certificate.
      </:content>
    </.tooltip>
    """
  end

  attr(:not_before, DateTime, required: true)
  attr(:not_after, DateTime, required: true)

  def certificate_status(assigns) do
    now = DateTime.utc_now()

    status =
      cond do
        DateTime.after?(now, assigns.not_after) ->
          "Expired"

        DateTime.before?(now, assigns.not_before) ->
          "Not Yet Valid"

        # Expires within the next three months. The shift was negative, which
        # put the cutoff three months in the past - a window the `Expired`
        # clause above has already taken, so this never matched.
        DateTime.after?(DateTime.shift(now, month: 3), assigns.not_after) ->
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

  # The `-content` colours are the ones defined for both themes; a bare
  # `text-alert` stays red-500 on the light theme, which is too hot.
  defp certificate_status_class("Expired"), do: "text-alert-content"
  defp certificate_status_class("Not Yet Valid"), do: "text-warning-content"
  defp certificate_status_class("Expiring Soon"), do: "text-warning-content"
  defp certificate_status_class("Current"), do: "text-content-muted"
end
