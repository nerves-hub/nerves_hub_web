defmodule NervesHubWeb.Components.DeviceExternalIdentities do
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

  alias NervesHub.Devices.ExternalIdentity

  attr(:identities, :list, default: [])
  attr(:enabled_device, :any, default: true)
  attr(:enabled_product, :any, default: true)

  # The extension governs whether a device may *report*; it does not make
  # already-recorded identities untrue. So switching it off explains an empty
  # panel rather than hiding values that are still perfectly valid.
  def render(%{identities: [], enabled_product: false} = assigns) do
    ~H"""
    <.frame>
      <div class="text-base-500 flex items-center gap-2 px-4 pt-2 pb-4">
        External identity reporting is not enabled for your product.
      </div>
    </.frame>
    """
  end

  def render(%{identities: [], enabled_device: false} = assigns) do
    ~H"""
    <.frame>
      <div class="text-base-500 flex items-center gap-2 px-4 pt-2 pb-4">
        External identity reporting is not enabled for this device.
      </div>
    </.frame>
    """
  end

  def render(%{identities: []} = assigns) do
    ~H"""
    <.frame>
      <div class="text-base-500 flex items-center gap-2 px-4 pt-2 pb-4">
        This device hasn't reported any external identities.
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
            <span class="text-base-300 text-sm font-medium">{service_name(identity.service)}</span>
            <%!-- Only worth naming when a device runs more than one endpoint of
            a service; saying "default" on every row is noise. --%>
            <span :if={named_instance?(identity)} class="bg-base-800 border-base-700 text-base-400 rounded border px-1.5 py-0.5 font-mono text-xs">
              {identity.instance}
            </span>
            <span :if={identity.source == :operator} class="bg-base-800 border-base-700 text-base-400 rounded border px-1.5 py-0.5 text-xs">
              set by operator
            </span>
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

          <div :if={identity.last_reported_at} class="text-base-500 text-xs tracking-wide">
            <span>Last reported: </span>
            <time
              id={"external-identity-#{identity.id}-reported-at"}
              phx-hook="UpdatingTimeAgo"
              datetime={String.replace(DateTime.to_string(DateTime.truncate(identity.last_reported_at, :second)), " ", "T")}
            >
              {Timex.from_now(identity.last_reported_at)}
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
    <div class="text-base-50 flex h-14 items-center pr-3 pl-4 leading-6 font-medium">
      External Identities
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
      <div id={@id} class="relative flex min-w-0" phx-hook={long_value?(@value) && "ToolTip"} data-placement="top">
        <div class="border-base-700 flex min-w-0 items-stretch overflow-hidden rounded border text-xs">
          <span class="bg-base-700 text-base-300 shrink-0 px-2 py-0.5 tracking-wide">{@label}</span>
          <span class="bg-base-800 text-base-200 min-w-0 truncate px-2 py-0.5 font-mono">{@value}</span>
        </div>
        <div :if={long_value?(@value)} role="tooltip" class="bg-surface-overlay border-base-700 tooltip-content absolute top-0 left-0 z-20 hidden max-w-md rounded border px-2 py-1.5 shadow-lg">
          <span class="text-base-200 font-mono text-xs break-all">{@value}</span>
          <div class="bg-surface-overlay border-base-700 tooltip-arrow absolute size-2 origin-center rotate-45"></div>
        </div>
      </div>
      <button
        id={"copy-#{@id}"}
        type="button"
        phx-hook="CopyToClipboard"
        data-copy-value={@value}
        aria-label={"Copy #{@label}"}
        title="Copy value"
        class="hover:text-base-200 text-base-500 shrink-0 cursor-pointer opacity-0 transition-opacity group-hover/identity:opacity-100 focus:opacity-100"
      >
        <span data-icon="copy" class="lucide-copy--light size-4"></span>
        <span data-icon="check" class="lucide-check--light text-success hidden size-4"></span>
      </button>
    </div>
    """
  end

  defp long_value?(value), do: String.length(value) > 32

  defp named_instance?(identity), do: identity.instance != ExternalIdentity.default_instance()

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
