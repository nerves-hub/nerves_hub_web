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
      <div :if={authorized?(:"device:console", @org_user) && @console_active?} class="flex flex-col size-full items-start justify-between">
        <div id="console-and-chat" class="size-full flex gap-4 p-6" phx-update="ignore">
          <div class="flex flex-col w-full bg-zinc-900 border border-zinc-700 rounded">
            <div class="flex justify-between items-center h-14 px-4 border-b border-zinc-700">
              <div id="console-title" class="text-base text-neutral-50 font-medium">Console</div>
            </div>
            <div id="dropzone" class="grow flex p-6 gap-6">
              <div id="console" phx-hook="Console" data-user-token={@user_token} data-device-id={@device.id} class="w-full h-full"></div>
            </div>
          </div>
        </div>
      </div>

      <div :if={authorized?(:"device:console", @org_user) && !@console_active?} class="flex flex-col size-full items-start justify-between">
        <div id="console-and-chat" class="size-full flex gap-4 p-6" phx-update="ignore">
          <div class="flex flex-col w-full bg-zinc-900 border border-zinc-700 rounded">
            <div class="flex justify-between items-center h-14 px-4 border-b border-zinc-700">
              <div class="text-base text-neutral-50 font-medium">Console</div>
            </div>
            <div class="grow flex justify-center items-center p-6 gap-6 text-medium">
              The device console isn't currently available.
            </div>
          </div>
        </div>
      </div>

      <div :if={!authorized?(:"device:console", @org_user)} class="flex flex-col size-full items-start justify-between">
        <div id="console-and-chat" class="size-full flex gap-4 p-6" phx-update="ignore">
          <div class="flex flex-col w-full bg-zinc-900 border border-zinc-700 rounded">
            <div class="flex justify-between items-center h-14 px-4 border-b border-zinc-700">
              <div class="text-base text-neutral-50 font-medium">Console</div>
            </div>
            <div class="grow flex justify-center items-center p-6 gap-6 text-medium text-red-500">
              You don't have the required permissions to access a Device console.
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
