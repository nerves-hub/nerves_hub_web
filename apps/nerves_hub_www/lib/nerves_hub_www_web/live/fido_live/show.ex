defmodule NervesHubWWWWeb.FidoLive.Show do
  use NervesHubWWWWeb, :live_view
  alias NervesHubWebCore.{Accounts, Accounts.FidoCredential}
  require Logger

  def mount(_params, %{"auth_user_id" => user_id}, socket) do
    socket =
      socket
      |> assign_new(:user, fn -> Accounts.get_user!(user_id) end)
      |> update(:user, &Accounts.User.with_fido_credentials/1)

    {:ok, socket, layout: {NervesHubWWWWeb.LayoutView, "live_flashes.html"}}
  rescue
    e ->
      socket_error(socket, live_view_error(e))
  end

  # Catch-all to handle when LV sessions change.
  # Typically this is after a deploy when the
  # session structure in the module has changed
  # for mount/3
  def mount(_, _, socket) do
    socket_error(socket, live_view_error(:update))
  end

  def render(%{live_action: :fido_nickname} = assigns) do
    ~H"""
    <.form let={f} for={@changeset} class="form-group" phx-change="validate-nickname" phx-submit="save-nickname">
      <%= label f, :nickname %>
      <%= text_input f, :nickname, class: "form-control", "phx-debounce": "100" %>
      <%= error_tag f, :nickname %>
      <div class="button-submit-wrapper">
        <a class="btn btn-secondary" phx-click="cancel">Cancel</a>
        <%= submit "Next", class: "btn btn-primary", disabled: not @changeset.valid? %>
      </div>
    </.form>
    """
  end

  def render(%{live_action: :register_fido} = assigns) do
    ~H"""
    <section id="fido-create" phx-hook="FidoCreate">
        <img src="/images/fingerprint-scanning.svg"/><br/>
        <p>Please press your authenticator now!</p>
        <div class="button-submit-wrapper">
          <button class="btn btn-primary" phx-click="retry-fido-credential-creation">Retry</button>
          <a class="btn btn-secondary" phx-click="cancel">Cancel</a>
        </div>
    </section>
    """
  end

  def render(assigns) do
    ~H"""
    <div class="action-row">
        <div class="flex-row align-items-center">
          <h1 class="mr-3 mb-0">FIDO Credentials</h1>
        </div>
        <div>
          <a class="btn btn-outline-light btn-action" aria-label="Register new key" phx-click="new-fido-credential">
              <div class="button-icon add"></div>
              <span class="action-text">Register new key</span>
          </a>
        </div>
    </div>

    <table id="fido_credentials" class="table table-sm table-hover">
        <thead>
          <tr>
              <th>Nickname</th>
              <th>Registration Date</th>
          </tr>
        </thead>
        <tbody>
          <%= for fido_credential <- @user.fido_credentials do %>
          <tr class="item">
              <td>
                  <div class="mobile-label help-text">Nickname</div>
                  <code class="color-white wb-ba"><%= fido_credential.nickname %></code>
              </td>
              <td title={fido_credential.inserted_at}>
                  <div class="mobile-label help-text">Registration Date</div>
                  <%= fido_credential.inserted_at %>
              </td>
              <td class="actions">
                  <div class="mobile-label help-text">Actions</div>
                  <div class="dropdown options">
                      <a class="dropdown-toggle options" href="#" id={to_string(fido_credential.id)} data-bs-toggle="dropdown" aria-haspopup="true" aria-expanded="false">
                          <div class="mobile-label pr-2">Open</div>
                          <img src="/images/icons/more.svg" alt="options" />
                      </a>
                      <div class="dropdown-menu dropdown-menu-right">
                          <button class="dropdown-item" type="button" phx-click="delete-fido-credential" phx-value-fido-credential-id={fido_credential.id} data-confirm="Are you sure?">
                              <span>Delete</span>
                          </button>
                      </div>
                  </div>
              </td>
          </tr>
          <% end %>
        </tbody>
    </table>
    """
  end

  def handle_event("cancel", _params, socket) do
    {:noreply, assign(socket, live_action: nil)}
  end

  def handle_event("new-fido-credential", _params, socket) do
    Logger.info("Starting FIDO Credential registration")

    socket =
      socket
      |> assign(:changeset, FidoCredential.nickname_changeset(%FidoCredential{}))
      |> assign(:live_action, :fido_nickname)
      |> clear_flash()

    {:noreply, socket}
  end

  def handle_event(
        "delete-fido-credential",
        %{"fido-credential-id" => id_str},
        %{assigns: %{user: user}} = socket
      ) do
    id = String.to_integer(id_str)
    target = Enum.find(user.fido_credentials, &(&1.id == id))

    case Accounts.delete_fido_credential(target) do
      {:ok, _} ->
        fido_credentials = Enum.reject(user.fido_credentials, &(&1.id == id))

        socket =
          socket
          |> put_flash(:info, "FIDO Credential deleted")
          |> assign(:user, %{user | fido_credentials: fido_credentials})

        {:noreply, socket}

      {:error, reason} ->
        Logger.warn(
          "Failed to delete FIDO Credential #{inspect(id_str)} with reason #{inspect(reason)}"
        )

        socket =
          socket
          |> put_flash(:error, "Failed to delete FIDO Credential")

        {:noreply, socket}
    end
  end

  def handle_event(
        "validate-nickname",
        %{"fido_credential" => %{"nickname" => nickname}} = _params,
        %{assigns: %{user: user}} = socket
      ) do
    changeset =
      %FidoCredential{}
      |> FidoCredential.nickname_changeset(%{nickname: nickname, user_id: user.id})
      |> Map.put(:action, :insert)

    {:noreply, assign(socket, changeset: changeset)}
  end

  def handle_event(
        "save-nickname",
        %{"fido_credential" => %{"nickname" => nickname}},
        socket
      ) do
    socket =
      socket
      |> assign(:live_action, :register_fido)
      |> assign(:nickname, nickname)
      |> trigger_fido_attestation()

    {:noreply, socket}
  end

  def handle_event("retry-fido-credential-creation", _params, socket) do
    socket = trigger_fido_attestation(socket)
    {:noreply, socket}
  end

  def handle_event(
        "fido-credential-created",
        %{
          "attestationObject" => attestation_object_b64,
          "clientDataJSON" => client_data_json_b64,
          "rawId" => raw_id_b64,
          "type" => "public-key" = type
        },
        %{assigns: %{challenge: challenge, nickname: nickname, user: user}} = socket
      ) do
    Logger.info("Received FIDO credential")

    attestation_object = Base.decode64!(attestation_object_b64)
    client_data_json = Base.decode64!(client_data_json_b64)

    with {:ok, {authenticator_data, _result}} <-
           Wax.register(attestation_object, client_data_json, challenge),
         {:ok, fido_credential} <-
           Accounts.create_fido_credential(%{
             user_id: user.id,
             nickname: nickname,
             credential_id: raw_id_b64,
             cose_key: authenticator_data.attested_credential_data.credential_public_key,
             type: type
           }) do
      Logger.info("Created FIDO credential")

      socket =
        socket
        |> put_flash(:info, "Security Key registered")
        |> assign(:live_action, nil)
        |> assign(:challenge, nil)
        |> assign(:user, %{user | fido_credentials: user.fido_credentials ++ [fido_credential]})

      {:noreply, socket}
    else
      {:error, reason} ->
        Logger.warn("Failed to register fibo key with reason #{inspect(reason)}")

        socket = put_flash(socket, :error, "Key registration failed")
        {:noreply, socket}
    end
  end

  defp trigger_fido_attestation(%{assigns: %{user: user}} = socket) do
    challenge = Wax.new_registration_challenge([])

    socket
    |> assign(:challenge, challenge)
    |> push_event(
      "create-fido-credential",
      %{
        user: %{
          id: encode_user_id(user.id),
          name: user.username,
          displayName: user.username
        },
        challenge: Base.encode64(challenge.bytes),
        rp: %{
          id: challenge.rp_id,
          name: "Nerves Hub Web"
        },
        attestation: challenge.attestation,
        pubKeyCredParams: [
          %{
            type: "public-key",
            # "ES256" IANA COSE Algorithms registry
            alg: -7
          }
        ]
      }
    )
  end

  defp encode_user_id(value) when is_number(value) do
    value
    |> Integer.to_string()
    |> Base.encode64()
  end
end
