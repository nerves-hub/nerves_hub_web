defmodule NervesHubWeb.Mounts.RequireEveryDevice do
  @moduledoc """
  Closes a page to members who see only some of the org's devices.

  For pages built from all of a product's devices, or from things that act on
  all of them: Insights, errors, deployment groups, firmware and the like. A
  member whose role is limited to tagged devices is sent to the devices they
  can see. See `NervesHub.Accounts.Scope.devices_limited?/1`.
  """
  use NervesHubWeb, :verified_routes

  import Phoenix.LiveView

  alias NervesHub.Accounts.Scope

  def on_mount(:default, _params, _session, socket) do
    scope = socket.assigns.current_scope

    if Scope.devices_limited?(scope) do
      socket =
        socket
        |> put_flash(:error, "Your role only gives you access to some of this organization's devices.")
        |> redirect(to: fallback_path(scope))

      {:halt, socket}
    else
      {:cont, socket}
    end
  end

  defp fallback_path(%Scope{org: org, product: nil}), do: ~p"/org/#{org}"
  defp fallback_path(%Scope{org: org, product: product}), do: ~p"/org/#{org}/#{product}/devices"
end
