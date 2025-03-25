defmodule NervesHubWeb.Components.DevicePage.Console do
  use NervesHubWeb, :live_component

  alias NervesHub.Tracker
  alias Phoenix.LiveView.JS

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

  def toggle_fullscreen(js \\ %JS{}) do
    js
    # Dropzone
    # disable relative
    |> JS.toggle_class("relative", to: "#dropzone")
    |> JS.toggle_class("fixed", to: "#dropzone")
    |> JS.toggle_class("top-0", to: "#dropzone")
    |> JS.toggle_class("left-0", to: "#dropzone")
    |> JS.toggle_class("right-0", to: "#dropzone")
    |> JS.toggle_class("bottom-0", to: "#dropzone")
    # disable p-12
    |> JS.toggle_class("p-12", to: "#dropzone")
    |> JS.toggle_class("p-6", to: "#dropzone")
    |> JS.toggle_class("pt-14", to: "#dropzone")
    |> JS.toggle_class("pb-4", to: "#dropzone")
    |> JS.toggle_class("box-border", to: "#dropzone")

    # Immersive device information
    |> JS.toggle(to: "#immersive-device")

    # Console
    |> JS.toggle_class("box-border", to: "#console")
    # disable w-full
    |> JS.toggle_class("w-full", to: "#console")
    # disable h-full
    |> JS.toggle_class("h-full", to: "#console")

    # Fullscreen/Close button
    # disable right-16
    |> JS.toggle_class("right-16", to: "#fullscreen")
    |> JS.toggle_class("right-4", to: "#fullscreen")
    # disable top-8
    |> JS.toggle_class("top-8", to: "#fullscreen")
    |> JS.toggle_class("top-4", to: "#fullscreen")
    |> JS.toggle_class("hidden", to: "#fullscreen svg")
  end

  def render(assigns) do
    ~H"""
    <div class="size-full">
      <div class="flex flex-col size-full items-start justify-between">
        <div id="console-and-chat" class="size-full flex bg-black" phx-update="ignore" style="background-color: rgb(14, 16, 25);">
          <div :if={authorized?(:"device:console", @org_user) && @console_active?} id="dropzone" class="grow flex p-12 gap-6 relative" style="background-color: rgb(14, 16, 25);">
            <div id="console" phx-hook="Console" data-user-token={@user_token} data-device-id={@device.id} class="w-full h-full z-10"></div>
            <div id="immersive-device" class="absolute top-4 left-6 z-20 text-neutral-800 pointer-events-none hidden">
              <div class="flex gap-3 items-center">
                <%= if Map.get(@device_connection || %{}, :status) == :connected do %>
                  <svg class="h-3 w-3" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 6 6" fill="none">
                    <circle cx="3" cy="3" r="3" fill="#10B981" />
                  </svg>
                <% else %>
                  <svg class="h-3 w-3" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 6 6" fill="none">
                    <circle cx="3" cy="3" r="3" fill="#71717A" />
                  </svg>
                <% end %>
                <h1 class="text-xl font-semibold leading-[30px] text-zinc-50 font-mono">
                  {@device.identifier}
                </h1>
              </div>
            </div>
            <button id="fullscreen" class="absolute top-8 right-16 z-20 rounded-full bg-neutral-900 cursor-pointer hover:scale-[1.1]" phx-click={toggle_fullscreen()} title="Toggle fullscreen">
              <svg class="stroke-neutral-50" width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
                <path d="M15 19H19M19 19V15M19 19L15 15M9 5H5M5 5V9M5 5L9 9M15 5H19M19 5V9M19 5L15 9M9 19H5M5 19V15M5 19L9 15" stroke-width="1" stroke-linecap="round" stroke-linejoin="round" />
              </svg>
              <svg class="stroke-neutral-50 hidden" width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
                <path d="M12 12L7 7M12 12L17 17M12 12L17 7M12 12L7 17" stroke-width="1" stroke-linecap="round" stroke-linejoin="round" />
              </svg>
            </button>
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
