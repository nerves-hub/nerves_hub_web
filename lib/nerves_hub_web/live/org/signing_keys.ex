defmodule NervesHubWeb.Live.Org.SigningKeys do
  use NervesHubWeb, :live_view

  alias NervesHub.Accounts
  alias NervesHub.Accounts.OrgKey
  alias NervesHub.Firmwares.UpdateTool.EspIdf

  @impl Phoenix.LiveView
  def mount(_params, _session, %{assigns: %{current_scope: scope}} = socket) do
    {:ok, assign(socket, :org, scope.org)}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> page_title("Signing Keys - #{socket.assigns.org.name}")
    |> assign(:signing_keys, list_signing_keys(socket.assigns.current_scope))
    |> sidebar_tab(:signing_keys)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> page_title("New Signing Key - #{socket.assigns.org.name}")
    |> assign(:form, to_form(Accounts.OrgKey.changeset(%Accounts.OrgKey{}, %{})))
    |> sidebar_tab(:signing_keys)
  end

  @impl Phoenix.LiveView
  def handle_event("save", %{"org_key" => key_params}, %{assigns: %{current_scope: scope}} = socket) do
    authorized!(:"signing_key:create", scope)

    params =
      key_params
      |> Enum.into(%{"org_id" => scope.org.id})
      |> Enum.into(%{"created_by_id" => scope.user.id})

    case Accounts.create_org_key(params) do
      {:ok, _org_key} ->
        {:noreply,
         socket
         |> put_flash(:info, "Signing Key created successfully.")
         |> push_navigate(to: ~p"/org/#{scope.org}/settings/keys")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("delete", %{"signing_key_id" => signing_key_id}, %{assigns: %{current_scope: scope}} = socket) do
    authorized!(:"signing_key:delete", scope)

    {:ok, signing_key} = Accounts.get_org_key(scope, signing_key_id)

    case Accounts.delete_org_key(signing_key) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Signing Key deleted successfully.")
         |> assign(:signing_keys, list_signing_keys(scope))}

      {:error, %Ecto.Changeset{} = changeset} ->
        message =
          changeset.errors
          |> Enum.map_join(", ", fn {_k, v} -> elem(v, 0) end)

        {:noreply, put_flash(socket, :error, "Error deleting Signing Key : " <> message)}
    end
  end

  defp list_signing_keys(scope), do: Accounts.list_org_keys(scope)

  defp scheme_options() do
    [
      {"fwup (Ed25519)", :ed25519},
      {"ESP-IDF Secure Boot v2 (RSA-3072)", :secure_boot_v2_rsa}
    ]
  end

  defp scheme_label(:ed25519), do: "ed25519"
  defp scheme_label(:secure_boot_v2_rsa), do: "secure-boot-v2-rsa"
  defp scheme_label(other), do: to_string(other)

  defp key_label(%{scheme: :secure_boot_v2_rsa}), do: "eFuse digest"
  defp key_label(_), do: nil

  # An Ed25519 key is one short line and is worth showing whole — it is how
  # operators recognise it.
  defp key_preview(%{scheme: :ed25519, key: key}), do: key

  # A PEM is 600+ bytes of base64 that reads the same for every key. The Secure
  # Boot v2 key digest is what `espsecure.py digest-sbv2-public-key` produces
  # and what is burned into a chip's eFuse, so it both identifies the key and
  # can be checked against the devices that will accept it.
  defp key_preview(%{key: key}) do
    case OrgKey.decode_rsa_public_key(key) do
      {:ok, rsa} -> EspIdf.key_digest(rsa)
      _ -> boundary_lines(key)
    end
  end

  defp boundary_lines(key) do
    key
    |> String.split("\n", trim: true)
    |> case do
      [first | rest] when rest != [] -> "#{first} … #{List.last(rest)}"
      other -> Enum.join(other, " ")
    end
  end
end
