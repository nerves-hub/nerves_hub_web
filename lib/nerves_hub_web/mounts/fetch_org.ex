defmodule NervesHubWeb.Mounts.FetchOrg do
  import Phoenix.Component

  def on_mount(:default, %{"org_name" => org_name}, _session, socket) do
    %{orgs: orgs} = socket.assigns

    org = Enum.find(orgs, &(&1.name == org_name))

    case !is_nil(org) do
      true ->
        {:cont, assign(socket, :org, org)}

      false ->
        raise Ecto.NoResultsError
    end
  end
end
