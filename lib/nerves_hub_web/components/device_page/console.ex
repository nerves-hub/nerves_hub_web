defmodule NervesHubWeb.Components.DevicePage.Console do
  use NervesHubWeb, :live_component

  alias NervesHub.Tracker

  def update(%{file_upload: payload}, socket) do
    if socket.user.id == payload.uploaded_by do
      case payload.status do
        "started" ->
          send_toast(socket, :info, "Upload started.")

        "finished" ->
          send_toast(socket, :info, "Upload finished.")

        _ ->
          true
      end
    end

    ok(socket)
  end

  def update(assigns, socket) do
    socket
    |> assign(assigns)
    |> assign(:user_token, Phoenix.Token.sign(socket, "user salt", assigns.user.id))
    |> assign(:console_active?, Tracker.console_active?(assigns.device))
    |> ok()
  end

  def render(assigns) do
    ~H"""
    <div class="size-full">
      <div class="flex flex-col size-full items-start justify-between">
        <div id="console-and-chat" class="size-full flex bg-black p-12" phx-update="ignore" style="background-color: rgb(14, 16, 25);">
          <div :if={authorized?(:"device:console", @org_user) && @console_active?} id="dropzone" class="grow">
            <div id="console" phx-hook="Console" data-user-token={@user_token} data-device-id={@device.id} class="w-full h-full"></div>
          </div>
          <div :if={authorized?(:"device:console", @org_user) && !@console_active?} class="grow flex justify-center items-center p-6 gap-6 text-medium font-mono">
            The device console isn't currently available.
          </div>
          <div :if={!authorized?(:"device:console", @org_user)} class="grow flex justify-center items-center p-6 gap-6 text-medium text-red-500 font-mono">
            You don't have the required permissions to access a Device console.
          </div>
        </div>
      </div>
    </div>
    """
  end
end
