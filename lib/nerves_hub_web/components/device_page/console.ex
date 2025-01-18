defmodule NervesHubWeb.Components.DevicePage.Console do
  use NervesHubWeb, :live_component

  alias NervesHub.Tracker

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
          <div class="flex flex-col w-9/12 bg-zinc-900 border border-zinc-700 rounded">
            <div class="flex justify-between items-center h-14 px-4 border-b border-zinc-700">
              <div class="text-base text-neutral-50 font-medium">Console</div>
            </div>
            <div id="dropzone" class="grow flex p-6 gap-6">
              <div id="console" phx-hook="Console" data-user-token={@user_token} data-device-id={@device.id} class="w-full h-full"></div>
            </div>
          </div>

          <div class="flex flex-col w-3/12 bg-zinc-900 border border-zinc-700 rounded">
            <div class="flex-none flex justify-between items-center h-14 px-4 border-b border-zinc-700">
              <div class="text-base text-neutral-50 font-medium">Chat</div>
            </div>
            <div class="flex-1 flex justify-between items-center h-14 p-4 border-b border-zinc-700">
              <pre id="chat-body" class="h-full leading-loose text-xs"></pre>
            </div>
            <div class="flex-none flex justify-between items-center h-14 px-4 border-b border-zinc-900 bg-zinc-900">
              <input id="chat-message" type="text" class="py-1.5 px-2 block w-full border-0 text-zinc-400 bg-zinc-900 ring-0 focus:ring-0 sm:text-sm" />
            </div>
          </div>
        </div>
      </div>

      <div :if={authorized?(:"device:console", @org_user) && !@console_active?} class="flex flex-col size-full items-start justify-between">
        <div id="console-and-chat" class="size-full flex gap-4 p-6" phx-update="ignore">
          <div class="flex flex-col w-9/12 bg-zinc-900 border border-zinc-700 rounded">
            <div class="flex justify-between items-center h-14 px-4 border-b border-zinc-700">
              <div class="text-base text-neutral-50 font-medium">Console</div>
            </div>
            <div class="grow flex justify-center items-center p-6 gap-6 text-medium">
              The device console isn't currently available.
            </div>
          </div>

          <div class="flex flex-col w-3/12 bg-zinc-900 border border-zinc-700 rounded">
            <div class="flex-none flex justify-between items-center h-14 px-4 border-b border-zinc-700">
              <div class="text-base text-neutral-50 font-medium">Chat</div>
            </div>
            <div class="flex-1 flex justify-between items-center h-14 p-4 border-b border-zinc-700">
              <pre id="chat-body" class="h-full leading-loose text-xs"></pre>
            </div>
            <div class="flex-none flex justify-between items-center h-14 px-4 border-b border-zinc-900 bg-zinc-900">
              <input id="chat-message" type="text" class="py-1.5 px-2 block w-full border-0 text-zinc-400 bg-zinc-900 ring-0 focus:ring-0 sm:text-sm" />
            </div>
          </div>
        </div>
      </div>

      <div :if={!authorized?(:"device:console", @org_user)} class="flex flex-col size-full items-start justify-between">
        <div id="console-and-chat" class="size-full flex gap-4 p-6" phx-update="ignore">
          <div class="flex flex-col w-9/12 bg-zinc-900 border border-zinc-700 rounded">
            <div class="flex justify-between items-center h-14 px-4 border-b border-zinc-700">
              <div class="text-base text-neutral-50 font-medium">Console</div>
            </div>
            <div class="grow flex justify-center items-center p-6 gap-6 text-medium text-red-500">
              You don't have the required permissions to access a Device console.
            </div>
          </div>

          <div class="flex flex-col w-3/12 bg-zinc-900 border border-zinc-700 rounded">
            <div class="flex-none flex justify-between items-center h-14 px-4 border-b border-zinc-700">
              <div class="text-base text-neutral-50 font-medium">Chat</div>
            </div>
            <div class="flex-1 flex justify-between items-center h-14 p-4 border-b border-zinc-700">
              <pre id="chat-body" class="h-full leading-loose text-xs"></pre>
            </div>
            <div class="flex-none flex justify-between items-center h-14 px-4 border-b border-zinc-900 bg-zinc-900">
              <input id="chat-message" type="text" class="py-1.5 px-2 block w-full border-0 text-zinc-400 bg-zinc-900 ring-0 focus:ring-0 sm:text-sm" />
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
