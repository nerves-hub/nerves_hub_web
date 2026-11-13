defmodule NervesHubWeb.Live.Org.Settings do
  use NervesHubWeb, :live_view

  alias NervesHub.Accounts
  alias NervesHub.Accounts.Org
  alias NervesHub.Products
  alias NervesHubWeb.Mounts.OrgCounts

  on_mount(OrgCounts)

  @impl Phoenix.LiveView
  def mount(_params, _session, %{assigns: %{current_scope: scope}} = socket) do
    socket
    |> page_title("Settings - #{scope.org.name}")
    |> assign(:org, scope.org)
    |> assign(:form, to_form(Org.changeset(scope.org)))
    |> assign(
      :product_names,
      scope |> Products.get_products() |> Enum.map(& &1.name) |> Enum.sort_by(&String.downcase/1)
    )
    |> sidebar_tab(:settings)
    |> ok()
  end

  @impl Phoenix.LiveView
  def handle_event("update", %{"org" => org_params}, %{assigns: %{current_scope: scope}} = socket) do
    authorized!(:"organization:update", scope)

    case Accounts.update_org(scope.org, org_params) do
      {:ok, org} ->
        socket
        |> put_flash(:info, "Organization updated")
        |> push_navigate(to: ~p"/org/#{org}/settings")
        |> noreply()

      {:error, changeset} ->
        socket
        |> assign(:form, to_form(changeset))
        |> noreply()
    end
  end

  # What deleting takes with it. A few products are named so it's clear which;
  # past that the count says enough.
  defp delete_summary(org, []), do: "Deletes #{org.name}. It has no products."
  defp delete_summary(org, [name]), do: "Deletes #{org.name} and its 1 product, #{name}"

  defp delete_summary(org, names) when length(names) <= 3 do
    {rest, [last]} = Enum.split(names, -1)
    "Deletes #{org.name} and its #{length(names)} products: #{Enum.join(rest, ", ")} and #{last}"
  end

  defp delete_summary(org, names), do: "Deletes #{org.name} and its #{length(names)} products"
end
