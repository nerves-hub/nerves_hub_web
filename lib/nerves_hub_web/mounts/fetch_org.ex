defmodule NervesHubWeb.Mounts.FetchOrg do
  import Phoenix.Component

  def on_mount(:default, %{"hashid" => hashid}, _session, socket) do
    %{user: %{orgs: orgs}} = socket.assigns

    {:ok, [id]} = decode(hashid)

    org = Enum.find(orgs, &(&1.id == id))

    case !is_nil(org) do
      true ->
        {:cont, assign(socket, :org, org)}

      false ->
        raise NervesHubWeb.NotFoundError
    end
  end

  defp decode(org_hashid) do
    hashid = Application.get_env(:nerves_hub, :hashid_for_orgs)
    Hashids.decode(hashid, org_hashid)
  end
end
