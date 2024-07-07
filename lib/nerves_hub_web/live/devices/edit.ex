defmodule NervesHubWeb.Live.Devices.Edit do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Devices

  def mount(%{"device_identifier" => device_identifier}, _session, socket) do
    {:ok, device} =
      Devices.get_device_by_identifier(socket.assigns.product.org, device_identifier)

    changeset = Ecto.Changeset.change(device)

    socket
    |> assign(:page_title, "Edit Device")
    |> assign(:device, device)
    |> assign(:form, to_form(changeset))
    |> ok()
  end

  def handle_event("update-device", %{"device" => device_params}, socket) do
    authorized!(:"device:update", socket.assigns.org_user)

    %{product: product, device: device, user: user} = socket.assigns

    message = "#{user.name} updated device #{device.identifier}"

    case Devices.update_device_with_audit(device, device_params, user, message) do
      {:ok, _device} ->
        socket
        |> put_flash(:info, "Device updated")
        |> push_navigate(to: ~p"/products/#{hashid(product)}/devices")
        |> noreply()

      {:error, changeset} ->
        socket
        |> assign(:form, to_form(changeset))
        |> noreply()
    end
  end

  defp tags_to_string(%Phoenix.HTML.Form{} = form) do
    form.data.tags
    |> tags_to_string()
  end

  defp tags_to_string(%{tags: tags}), do: tags_to_string(tags)
  defp tags_to_string(tags) when is_list(tags), do: Enum.join(tags, ",")
  defp tags_to_string(tags), do: tags
end
