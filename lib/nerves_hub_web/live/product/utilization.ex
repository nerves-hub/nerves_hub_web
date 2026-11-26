defmodule NervesHubWeb.Live.Product.Utilization do
  @moduledoc """
  How much of NervesHub a product is using, as a checklist.

  The page draws `NervesHub.Products.Utilization.report/1`: the score, how
  the product's devices authenticate, the recommended features, and then the
  optional ones as a bonus. It changes nothing itself. Each item links to the
  documentation, and to the page here where the feature is turned on when
  there is one.

  `nh checklist` prints the same report from the API.
  """

  use NervesHubWeb, :live_view

  import NervesHubWeb.Components.ProductSettings, only: [title: 1, tabs: 1]
  import Number.Delimit, only: [number_to_delimited: 2]

  alias NervesHub.Products.ApiKeys
  alias NervesHub.Products.HealthProfiles
  alias NervesHub.Products.Utilization
  alias NervesHubWeb.Mounts.RequireEveryDevice

  on_mount(RequireEveryDevice)

  @decorate requires_membership()
  def mount(_params, _session, socket) do
    product = socket.assigns.current_scope.product
    report = Utilization.report(product)

    socket
    |> assign(:page_title, "#{product.name} Utilization")
    |> sidebar_tab(:settings)
    |> assign(:product, product)
    |> assign(:profile_count, HealthProfiles.count_for_product(product))
    |> assign(:api_key_count, ApiKeys.active_count(product))
    |> assign(:report, report)
    |> assign(:authentication, Enum.filter(report.items, &(&1.group == :authentication)))
    |> assign(:recommended, Enum.filter(report.items, &(&1.group == :recommended)))
    |> assign(:optional, Enum.filter(report.items, &(&1.group == :optional)))
    |> ok()
  end

  defp card_class(),
    do: "flex w-full flex-col overflow-clip rounded-card border border-line-default bg-surface-raised shadow-card"

  defp percent(%{total: 0}), do: 0
  defp percent(%{done: done, total: total}), do: round(done * 100 / total)

  defp headline(%{done: total, total: total}), do: "Every recommended feature is in use."
  defp headline(%{done: 0}), do: "None of the recommended features are in use yet."

  defp headline(%{done: done, total: total}) do
    "#{total - done} recommended #{if total - done == 1, do: "feature is", else: "features are"} still to turn on."
  end

  defp done_count(items), do: Enum.count(items, &(&1.status == :done))

  # What the instance can't offer isn't scored, so it isn't counted here.
  defp available_count(items), do: Enum.count(items, &(&1.status != :unavailable))

  # Where in the dashboard an item is turned on. One with no entry is turned
  # on in firmware.
  @places %{
    "device_auth" => :certificates,
    "jitp" => :certificates,
    "signed_firmware" => :firmware,
    "deployments" => :deployment_groups,
    "delta_updates" => :deployment_groups,
    "deployment_workflow" => :deployment_groups,
    "priority_queue" => :deployment_groups,
    "health" => :settings,
    "geo" => :settings,
    "logging" => :settings,
    "error_reports" => :settings,
    "local_shell" => :settings,
    "network_identity" => :settings,
    "device_managed_updates" => :settings,
    "other_firmware_formats" => :settings,
    "ci_api_key" => :api_keys,
    "notifications" => :integrations,
    "two_factor" => :org_settings,
    "archives" => :archives,
    "support_scripts" => :scripts,
    "platform_health_profiles" => :health_profiles,
    "custom_roles" => :roles
  }

  defp place(key, %{org: org, product: product}) do
    case Map.fetch(@places, key) do
      {:ok, place} -> link_to(place, org, product)
      :error -> nil
    end
  end

  defp link_to(:certificates, org, _product), do: {"Certificates", ~p"/org/#{org}/settings/certificates"}
  defp link_to(:integrations, org, _product), do: {"Integrations", ~p"/org/#{org}/settings/integrations"}
  defp link_to(:org_settings, org, _product), do: {"Organization settings", ~p"/org/#{org}/settings"}
  defp link_to(:roles, org, _product), do: {"Roles", ~p"/org/#{org}/settings/roles"}
  defp link_to(:firmware, org, product), do: {"Firmware", ~p"/org/#{org}/#{product}/firmware"}
  defp link_to(:archives, org, product), do: {"Archives", ~p"/org/#{org}/#{product}/archives"}
  defp link_to(:scripts, org, product), do: {"Support scripts", ~p"/org/#{org}/#{product}/scripts"}
  defp link_to(:settings, org, product), do: {"Product settings", ~p"/org/#{org}/#{product}/settings"}
  defp link_to(:api_keys, org, product), do: {"API keys", ~p"/org/#{org}/#{product}/settings/api_keys"}
  defp link_to(:health_profiles, org, product), do: {"Device health", ~p"/org/#{org}/#{product}/settings/health"}

  defp link_to(:deployment_groups, org, product) do
    {"Deployment groups", ~p"/org/#{org}/#{product}/deployment_groups"}
  end

  attr(:items, :list, required: true)
  attr(:current_scope, :map, required: true)

  defp items(assigns) do
    ~H"""
    <div
      :for={item <- @items}
      id={"utilization-#{item.key}"}
      data-status={item.status}
      class="flex items-start gap-3 border-t border-line-default px-4 py-3.5"
    >
      <.status_icon status={item.status} />
      <div class="flex min-w-0 flex-1 flex-col gap-1">
        <h3 class="text-sm/5 font-medium text-content-strong">{item.title}</h3>
        <p class="text-ui/4.5 text-content-body">{item.summary}</p>
        <p class="text-ui/4.5 text-content-muted">{item.description}</p>
        <p class="flex flex-wrap items-center gap-x-4 gap-y-1 pt-0.5 text-ui/4.5">
          <.link
            :if={place = place(item.key, @current_scope)}
            navigate={elem(place, 1)}
            class="font-medium text-notice-content hover:underline"
          >
            {elem(place, 0)}
          </.link>
          <a href={item.docs_url} target="_blank" rel="noopener noreferrer" class="inline-flex items-center gap-1 text-content-muted hover:text-content-strong hover:underline">
            Documentation <span class="lucide-external-link size-3" aria-hidden="true"></span>
          </a>
        </p>
      </div>
    </div>
    """
  end

  attr(:status, :atom, required: true)

  # The icon is the whole status: the summary beside it says what was found,
  # so there is no badge repeating it.
  defp status_icon(assigns) do
    ~H"""
    <span class={["mt-0.5 size-4 shrink-0", icon_class(@status)]} role="img" aria-label={icon_label(@status)}></span>
    """
  end

  defp icon_class(:done), do: "lucide-circle-check text-success"
  defp icon_class(:attention), do: "lucide-circle-question-mark text-warning"
  defp icon_class(:unavailable), do: "lucide-circle-slash text-content-faint"
  defp icon_class(:todo), do: "lucide-circle-dashed text-content-faint"

  defp icon_label(:done), do: "In use"
  defp icon_label(:attention), do: "Warning"
  defp icon_label(:unavailable), do: "Not available on this instance"
  defp icon_label(:todo), do: "Not in use"
end
