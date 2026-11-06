defmodule NervesHubWeb.Components.DeviceNetworkIdentities do
  @moduledoc """
  Shows the identities a device holds on networks NervesHub does not run.

  The identifier is given prominence and made copyable — the values here are
  long (an iroh ticket runs to a couple of hundred base32 characters) and exist
  to be pasted into something else, which is the whole point of surfacing them.

  `details` is rendered generically as key/value pairs. It is free-form and
  service-defined by design, so enumerating its keys here would just be a second
  place to keep in step with every integration.
  """

  use NervesHubWeb, :component

  alias NervesHub.Devices.NetworkIdentity
  alias NervesHub.Helpers.RelativeTime

  attr(:identities, :list, default: [])
  attr(:enabled_device, :any, default: true)
  attr(:enabled_product, :any, default: true)

  # The extension governs whether a device may *report*; it does not make
  # already-recorded identities untrue. So switching it off explains an empty
  # panel rather than hiding values that are still perfectly valid.
  def render(%{identities: [], enabled_product: false} = assigns) do
    ~H"""
    <.frame>
      <div class="flex items-center gap-2 px-4 pt-2 pb-4 text-content-faint">
        External identity reporting is not enabled for your product.
      </div>
    </.frame>
    """
  end

  def render(%{identities: [], enabled_device: false} = assigns) do
    ~H"""
    <.frame>
      <div class="flex items-center gap-2 px-4 pt-2 pb-4 text-content-faint">
        External identity reporting is not enabled for this device.
      </div>
    </.frame>
    """
  end

  def render(%{identities: []} = assigns) do
    ~H"""
    <.frame>
      <div class="flex items-center gap-2 px-4 pt-2 pb-4 text-content-faint">
        This device hasn't reported any network identities.
      </div>
    </.frame>
    """
  end

  def render(assigns) do
    ~H"""
    <.frame>
      <div class="flex flex-col gap-4 px-4 pt-1 pb-4">
        <%!-- Sorted here rather than in the query: these arrive as a join
        preload, whose ordering isn't guaranteed. --%>
        <div :for={identity <- Enum.sort_by(@identities, &{&1.service, &1.instance})} class="flex flex-col gap-1.5">
          <div class="flex items-center gap-2">
            <span class="text-sm font-medium text-content-body">{service_name(identity.service)}</span>
            <%!-- Only worth naming when a device runs more than one endpoint of
            a service; saying "default" on every row is noise. --%>
            <.tag :if={named_instance?(identity)} mono>
              {identity.instance}
            </.tag>
            <.tag :if={identity.source == :operator}>
              set by operator
            </.tag>
          </div>

          <.value_pill
            id={"external-identity-#{identity.id}"}
            label={identifier_label(identity.service)}
            value={identity.identifier}
          />

          <.value_pill
            :for={{key, value} <- detail_entries(identity.details)}
            id={"external-identity-#{identity.id}-#{key}"}
            label={humanize(key)}
            value={value}
          />

          <div :if={identity.last_reported_at} class="text-xs tracking-wide text-content-faint">
            <span>Last reported: </span>
            <time
              id={"external-identity-#{identity.id}-reported-at"}
              phx-hook="UpdatingTimeAgo"
              datetime={String.replace(DateTime.to_string(DateTime.truncate(identity.last_reported_at, :second)), " ", "T")}
            >
              {RelativeTime.from_now(identity.last_reported_at)}
            </time>
          </div>
        </div>
      </div>
    </.frame>
    """
  end

  slot(:inner_block, required: true)

  defp frame(assigns) do
    ~H"""
    <div class="flex h-14 items-center px-4 text-card-title text-content-strong">
      Network Identities
    </div>
    {render_slot(@inner_block)}
    """
  end

  attr(:id, :string, required: true)
  attr(:label, :string, required: true)
  attr(:value, :string, required: true)

  # The two-tone pill, hover tooltip and copy button match the device metadata
  # display, which solves exactly this problem: a value too long for the column
  # that still needs to be read and copied in full.
  defp value_pill(assigns) do
    ~H"""
    <div class="group/identity flex w-full min-w-0 items-center gap-1.5">
      <.tooltip id={@id} placement="top" class="flex min-w-0" content_class="max-w-md" enabled={long_value?(@value)}>
        <div class="flex min-w-0 items-stretch overflow-hidden rounded border border-line-default text-xs">
          <span class="shrink-0 bg-base-700 px-2 py-0.5 tracking-wide text-content-body">{@label}</span>
          <span class="min-w-0 truncate bg-base-800 px-2 py-0.5 font-mono text-base-200">{@value}</span>
        </div>
        <:content>
          <span class="font-mono text-xs break-all text-base-200">{@value}</span>
        </:content>
      </.tooltip>
      <button
        id={"copy-#{@id}"}
        type="button"
        phx-hook="CopyToClipboard"
        data-copy-value={@value}
        aria-label={"Copy #{@label}"}
        title="Copy value"
        class="shrink-0 cursor-pointer text-content-faint opacity-0 transition-opacity group-hover/identity:opacity-100 hover:text-base-200 focus:opacity-100"
      >
        <span data-icon="copy" class="lucide-copy size-4"></span>
        <span data-icon="check" class="lucide-check hidden size-4 text-success"></span>
      </button>
    </div>
    """
  end

  defp long_value?(value), do: String.length(value) > 32

  defp named_instance?(identity), do: identity.instance != NetworkIdentity.default_instance()

  # Brand capitalisation, which no generic humanising of the atom gets right.
  defp service_name(:iroh), do: "iroh"
  defp service_name(:netbird), do: "NetBird"
  defp service_name(:tailscale), do: "Tailscale"
  defp service_name(:wireguard), do: "WireGuard"

  # What the identifier *is* differs by service, even though it is always the
  # key the device proves it holds.
  defp identifier_label(:iroh), do: "Endpoint id"
  defp identifier_label(_service), do: "Public key"

  defp detail_entries(details) when is_map(details) do
    details
    |> Enum.reject(fn {_key, value} -> value in ["", nil] end)
    |> Enum.map(fn {key, value} -> {to_string(key), detail_value(value)} end)
    |> Enum.sort_by(fn {key, _value} -> key end)
  end

  defp detail_entries(_details), do: []

  # Details come back from jsonb, so a value can be any decoded JSON term.
  defp detail_value(value) when is_binary(value), do: value
  defp detail_value(value) when is_list(value), do: Enum.map_join(value, ", ", &detail_value/1)
  defp detail_value(value) when is_number(value) or is_boolean(value), do: to_string(value)
  defp detail_value(value), do: inspect(value)

  # Detail keys are full of networking acronyms, and plain capitalisation turns
  # them into "Fqdn", "Ipv4" and "Alpn", which just reads as a bug.
  @acronyms %{
    "alpn" => "ALPN",
    "api" => "API",
    "dns" => "DNS",
    "fqdn" => "FQDN",
    "id" => "ID",
    "ip" => "IP",
    "ips" => "IPs",
    "ipv4" => "IPv4",
    "ipv6" => "IPv6",
    "mac" => "MAC",
    "mtu" => "MTU",
    "os" => "OS",
    "ssid" => "SSID",
    "tcp" => "TCP",
    "udp" => "UDP",
    "uri" => "URI",
    "url" => "URL",
    "urls" => "URLs"
  }

  defp humanize(key) do
    key
    |> String.replace("_", " ")
    |> String.split(" ", trim: true)
    |> Enum.with_index()
    |> Enum.map_join(" ", fn {word, index} -> humanize_word(word, index) end)
  end

  defp humanize_word(word, index) do
    case Map.fetch(@acronyms, String.downcase(word)) do
      {:ok, acronym} -> acronym
      :error when index == 0 -> String.capitalize(word)
      :error -> String.downcase(word)
    end
  end
end
