defmodule NervesHubWeb.Live.Devices.New do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Devices
  alias NervesHub.Devices.Device

  def mount(_params, _session, socket) do
    changeset = Ecto.Changeset.change(%Device{})

    socket
    |> page_title("New Device - #{socket.assigns.product.name}")
    |> assign(:tab_hint, :devices)
    |> assign(:form, to_form(changeset))
    |> ok()
  end

  def handle_event("save-device", %{"device" => device_params}, socket) do
    authorized!(:"device:create", socket.assigns.org_user)

    %{org: org, product: product} = socket.assigns

    device_params
    |> Map.put("org_id", org.id)
    |> Map.put("product_id", product.id)
    |> Devices.create_device()
    |> case do
      {:ok, _device} ->
        socket
        |> put_flash(:info, "Device created successfully.")
        |> push_navigate(to: ~p"/org/#{org.name}/#{product.name}/devices")
        |> noreply()

      {:error, changeset} ->
        socket
        |> assign(:form, to_form(changeset))
        |> put_flash(:error, "Failed to add new device.")
        |> noreply()
    end
  end

  defp tags_to_string(%Phoenix.HTML.FormField{} = field) do
    tags_to_string(field.value)
  end

  defp tags_to_string(%{tags: tags}), do: tags_to_string(tags)
  defp tags_to_string(tags) when is_list(tags), do: Enum.join(tags, ", ")
  defp tags_to_string(tags), do: tags
end
