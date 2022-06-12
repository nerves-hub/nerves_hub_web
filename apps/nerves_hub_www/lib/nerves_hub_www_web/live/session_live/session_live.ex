defmodule NervesHubWWWWeb.SessionLive do
  use NervesHubWWWWeb, :live_view
  require Logger

  def mount(_params, %{"fido_challenge" => fido_challenge}, socket) do
    socket =
      socket
      |> assign(:fido_challenge, fido_challenge)
      |> trigger_get_fido_credential()
      |> assign(trigger_submit: false)

    {:ok, socket, layout: {NervesHubWWWWeb.LayoutView, "live_flashes.html"}}
  end

  def render(assigns) do
    ~H"""
    <div class="form-page-wrapper" id="fido-get" phx-hook="FidoGet">
      <h2 class="form-title">Login</h2>
      <.form let={f} for={:fido} class="form-page" action={Routes.session_path(@socket, :fido)} phx-trigger-action={@trigger_submit}>
        <%= Enum.map([:raw_id, :authenticator_data, :signature, :client_data_json], &hidden_input(f, &1, value: assigns[&1]))  %>
        <div class="form-group">
          <img src="/images/fingerprint-scanning.svg"/><br/>
          <p>Please press your authenticator now!</p>
          <div class="flex-column align-items-center gap-10px">
            <div class="btn btn-primary btn-lg w-100 mb-2" phx-click="retry">
              Retry
            </div>
            <div class="btn btn-outline-light  btn-lg w-50" phx-click="cancel">
              Cancel
            </div>
          </div>
        </div>
      </.form>
    </div>
    """
  end

  def handle_event(
        "fido-credential-received",
        %{
          "rawId" => raw_id,
          "response" => %{
            "authenticatorData" => authenticator_data,
            "signature" => signature,
            "clientDataJSON" => client_data_json
          }
        },
        socket
      ) do
    socket =
      socket
      |> assign(
        raw_id: raw_id,
        authenticator_data: authenticator_data,
        signature: signature,
        client_data_json: client_data_json,
        trigger_submit: true
      )

    {:noreply, socket}
  end

  def handle_event("fido-authentication-failed", _, socket) do
    Logger.debug("Fido authentication failed")
    socket = put_flash(socket, :error, "FIDO authentication failed") |> IO.inspect()
    {:noreply, socket}
  end

  def handle_event("retry", _, socket) do
    socket = socket |> clear_flash() |> trigger_get_fido_credential()
    {:noreply, socket}
  end

  def handle_event("cancel", _, socket) do
    socket = redirect(socket, to: Routes.session_path(socket, :new))
    {:noreply, socket}
  end

  defp trigger_get_fido_credential(
         %{assigns: %{fido_challenge: %Wax.Challenge{} = challenge}} = socket
       ) do
    socket
    |> push_event(
      "get-fido-credential",
      %{
        challenge: Base.encode64(challenge.bytes),
        rpId: challenge.rp_id,
        allowCredentials:
          Enum.map(challenge.allow_credentials, fn {id, _} -> %{id: id, type: "public-key"} end)
      }
    )
  end
end
