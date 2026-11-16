defmodule NervesHubWeb.Mounts.OrgCounts do
  @moduledoc """
  Keeps `@org_counts` on an organization page, for the header and tabs
  `NervesHubWeb.Layouts.org/1` draws: how many products, devices, members,
  signing keys and certificate authorities the organization has.

  The counts are taken on every `handle_params`, so a page that adds or
  removes one and then patches or navigates shows the new number. A page that
  changes one without either calls `refresh/1`.

      on_mount NervesHubWeb.Mounts.OrgCounts
  """
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4]

  alias NervesHub.Accounts
  alias Phoenix.LiveView.Socket

  def on_mount(:default, _params, _session, socket) do
    socket =
      attach_hook(socket, :org_counts, :handle_params, fn _params, _uri, socket ->
        {:cont, refresh(socket)}
      end)

    {:cont, socket}
  end

  @doc "Counts the current organization's products, devices, members, keys and certificates again."
  @spec refresh(Socket.t()) :: Socket.t()
  def refresh(%{assigns: %{current_scope: %{org: org, user: user}}} = socket) do
    assign(socket, :org_counts, Accounts.org_counts(org, user))
  end
end
