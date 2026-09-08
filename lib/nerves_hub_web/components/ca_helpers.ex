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
    <div class="relative z-20 flex items-center" id={@id} phx-hook="ToolTip" data-placement={@placement}>
      <.icon name="info" class="stroke-base-400" />
      <div class="bg-surface-muted border-base-700 tooltip-content absolute top-0 left-0 z-20 hidden w-max max-w-72 rounded border px-2 py-1.5 text-xs">
        By default, the time validity of CA certificates is unchecked. You can
        toggle this to check expiration to prevent device certificates
        from being created from an expired signing CA certificate.
        <div class="bg-surface-muted border-base-700 tooltip-arrow absolute size-2 origin-center rotate-45"></div>
      </div>
    </div>
    """
  end

  def certificate_status(assigns) do
    status =
      cond do
        DateTime.after?(DateTime.utc_now(), assigns.not_after) ->
          "Expired"

        # Expires within the next three months. The shift was negative, which
        # put the cutoff three months in the past - a window the `Expired`
        # clause above has already taken, so this never matched.
        DateTime.after?(DateTime.shift(DateTime.utc_now(), month: 3), assigns.not_after) ->
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
  defp certificate_status_class("Expiring Soon"), do: "text-warning-content"
  defp certificate_status_class("Current"), do: "text-base-400"
end
