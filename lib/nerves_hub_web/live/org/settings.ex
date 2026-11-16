defmodule NervesHubWeb.Live.Org.Settings do
  use NervesHubWeb, :live_view

  alias NervesHub.Accounts
  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.TwoFactor
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
    |> assign_two_factor()
    |> sidebar_tab(:settings)
    |> ok()
  end

  defp assign_two_factor(%{assigns: %{current_scope: scope}} = socket) do
    socket
    |> assign(:two_factor_available?, TwoFactor.available?())
    |> assign(:own_two_factor?, TwoFactor.enabled?(scope.user))
    |> assign(:members_without_two_factor, TwoFactor.members_without(socket.assigns.org))
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

  def handle_event("update-two-factor", params, %{assigns: %{current_scope: scope}} = socket) do
    authorized!(:"organization:update", scope)

    required = params["require_two_factor"] == "true"

    case TwoFactor.set_org_requirement(socket.assigns.org, scope.user, required) do
      {:ok, org} ->
        message =
          if org.require_two_factor,
            do: "Members now need two-factor authentication to reach #{org.name}.",
            else: "#{org.name} no longer requires two-factor authentication."

        socket
        |> put_flash(:info, message)
        |> push_navigate(to: ~p"/org/#{org}/settings")
        |> noreply()

      {:error, :two_factor_off} ->
        socket
        |> put_flash(:error, "Turn on two-factor authentication for your own account first.")
        |> noreply()

      {:error, :unavailable} ->
        socket
        |> put_flash(:error, "Two-factor authentication isn't available on this server.")
        |> noreply()

      {:error, _changeset} ->
        socket
        |> put_flash(:error, "The setting couldn't be saved. Try again.")
        |> noreply()
    end
  end

  defp member_names(users) do
    names = Enum.map(users, & &1.name)

    case Enum.split(names, 5) do
      {shown, []} -> join_names(shown)
      {shown, rest} -> Enum.join(shown, ", ") <> " and #{length(rest)} more"
    end
  end

  defp join_names([name]), do: name

  defp join_names(names) do
    {rest, [last]} = Enum.split(names, -1)
    Enum.join(rest, ", ") <> " and " <> last
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
