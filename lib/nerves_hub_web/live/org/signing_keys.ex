defmodule NervesHubWeb.Live.Org.SigningKeys do
  use NervesHubWeb, :live_view

  alias NervesHub.Accounts
  alias NervesHub.Accounts.OrgKey
  alias NervesHub.Firmwares.UpdateTool.EspIdf
  alias NervesHubWeb.Mounts.OrgCounts

  on_mount(OrgCounts)

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
    |> load_keys()
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

    case Accounts.create_org_key(scope.org, scope.user, key_params) do
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
         |> load_keys()
         |> OrgCounts.refresh()}

      {:error, %Ecto.Changeset{} = changeset} ->
        message =
          changeset.errors
          |> Enum.map_join(", ", fn {_k, v} -> elem(v, 0) end)

        {:noreply, put_flash(socket, :error, "Error deleting Signing Key : " <> message)}
    end
  end

  defp load_keys(%{assigns: %{current_scope: scope}} = socket) do
    socket
    |> assign(:signing_keys, Accounts.list_org_keys(scope))
    |> assign(:usage, Accounts.org_key_usage(scope.org))
  end

  defp scheme_options() do
    [
      {"fwup (Ed25519)", :ed25519},
      {"ESP-IDF Secure Boot v2 (RSA-3072)", :secure_boot_v2_rsa},
      {"RAUC (X.509 certificate)", :x509_certificate}
    ]
  end

  # Which update tool the key is for, then what kind of key it is.
  defp scheme_label(:ed25519), do: "fwup · Ed25519"
  defp scheme_label(:secure_boot_v2_rsa), do: "ESP-IDF · RSA-3072"
  defp scheme_label(:x509_certificate), do: "RAUC · X.509 certificate"
  defp scheme_label(other), do: to_string(other)

  defp added(%OrgKey{inserted_at: inserted_at}), do: Calendar.strftime(inserted_at, "%B %Y")

  defp unused?(%{firmware: 0, archives: 0}), do: true
  defp unused?(_usage), do: false

  defp usage_label(usage) do
    case usage_parts(usage) do
      [] -> "Not used yet"
      parts -> Enum.join(parts, ", ")
    end
  end

  defp usage_parts(%{firmware: firmware, archives: archives}) do
    [
      firmware > 0 && "#{firmware} firmware",
      archives == 1 && "1 archive",
      archives > 1 && "#{archives} archives"
    ]
    |> Enum.filter(& &1)
  end

  # Why the menu's Delete is greyed out. Firmware and archives hold the key by
  # a foreign key, so it can't go while they're there.
  defp delete_blocked_reason(_usage, false), do: "Your role doesn't let you delete signing keys."

  defp delete_blocked_reason(%{firmware: firmware, archives: archives} = usage, true) do
    verb = if firmware + archives == 1, do: "is", else: "are"
    "#{usage |> usage_parts() |> Enum.join(" and ")} #{verb} signed with it."
  end

  defp toggle_menu(key_id) do
    JS.toggle(
      to: "#signing-key-#{key_id}-menu",
      in: {"ease-out duration-150", "opacity-0", "opacity-100"},
      out: {"ease-out duration-150", "opacity-100", "opacity-0"}
    )
  end

  defp hide_menu(js \\ %JS{}, key_id) do
    JS.hide(js,
      to: "#signing-key-#{key_id}-menu",
      transition: {"ease-out duration-150", "opacity-100", "opacity-0"}
    )
  end

  defp key_label(%{scheme: :secure_boot_v2_rsa}), do: "eFuse digest"
  defp key_label(%{scheme: :x509_certificate}), do: "SHA-256 fingerprint"
  defp key_label(_), do: nil

  # An Ed25519 key is one short line and is worth showing whole — it is how
  # operators recognise it.
  defp key_preview(%{scheme: :ed25519, key: key}), do: key

  # RAUC verifies a bundle's CMS signature against a certificate chain, so the
  # organization key is a certificate rather than a bare public key. The
  # fingerprint is what identifies it, and what can be checked against the
  # keyring an image was built with.
  defp key_preview(%{scheme: :x509_certificate, key: key}) do
    case OrgKey.certificate_fingerprint(key) do
      {:ok, fingerprint} -> fingerprint
      _ -> boundary_lines(key)
    end
  end

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
