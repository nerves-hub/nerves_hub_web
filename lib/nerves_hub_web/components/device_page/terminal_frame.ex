defmodule NervesHubWeb.Components.DevicePage.TerminalFrame do
  @moduledoc """
  The card the Console and System Shell tabs draw their terminal in: a toolbar
  saying whether the session is live, then the terminal on a fixed dark
  background, which stays dark in light mode because xterm draws its own
  colours.

  The element IDs are looked up by the terminal hooks in `assets/js`:
  `dropzone` takes dropped files, `fullscreen` is listened to for refitting the
  terminal, and `option-as-meta` is revealed on a Mac.
  """

  use NervesHubWeb, :component

  alias Phoenix.LiveView.JS

  @terminal_background "background-color: rgb(14, 16, 25);"

  attr(:terminal_id, :string, required: true, doc: "the ID of the element the terminal hook draws in")
  attr(:status, :atom, required: true, values: [:connected, :checking, :unavailable])
  attr(:identifier, :string, required: true)
  attr(:note, :string, default: nil, doc: "beside the status, such as who else sees the session")
  attr(:hint, :string, default: nil, doc: "at the end of the toolbar, before the controls")
  slot(:inner_block, required: true, doc: "the terminal, or a message in its place")

  def frame(assigns) do
    assigns = assign(assigns, :background, @terminal_background)

    ~H"""
    <div class="flex size-full flex-col p-4 sm:p-6">
      <div
        id={if(@status == :connected, do: "dropzone", else: "terminal-frame")}
        class="relative flex min-h-0 flex-1 flex-col overflow-hidden rounded-card border border-line-default shadow-card"
        style={@background}
      >
        <div class="flex h-11 shrink-0 items-center gap-3 border-b border-white/10 px-3.5 text-xs text-neutral-400">
          <span class={[
            "flex h-5.5 items-center gap-1.5 rounded-full px-2 font-medium",
            @status == :connected && "bg-emerald-400/10 text-emerald-300",
            @status != :connected && "bg-white/5 text-neutral-400"
          ]}>
            <span class={[
              "size-1.5 rounded-full",
              @status == :connected && "bg-emerald-400",
              @status == :checking && "animate-pulse bg-neutral-400",
              @status == :unavailable && "bg-neutral-500"
            ]} />
            {status_label(@status)}
          </span>
          <span id={"#{@terminal_id}-immersive"} class="hidden font-mono text-neutral-200">{@identifier}</span>
          <span :if={@note && @status == :connected} class="hidden truncate md:inline">{@note}</span>
          <span :if={@hint && @status == :connected} class="ml-auto hidden truncate text-neutral-500 lg:inline">{@hint}</span>

          <div :if={@status == :connected} id="terminal-controls" phx-update="ignore" class={["flex items-center gap-2", if(@hint, do: "max-lg:ml-auto", else: "ml-auto")]}>
            <label
              class="hidden h-6.5 cursor-pointer items-center gap-1.5 rounded border border-white/10 px-2 text-neutral-300 hover:border-white/20"
              title="Send ⌥ (Option) to the device as Meta, for shortcuts such as M-b and M-f. Leave this off to type characters like [ ] { } | on non-US keyboard layouts."
            >
              <input type="checkbox" id="option-as-meta" class="size-3 rounded-sm border-white/30 bg-transparent text-primary checked:bg-primary focus:ring-0" />
              <span>⌥ as Meta</span>
            </label>
            <button
              id="fullscreen"
              type="button"
              class="flex size-6.5 cursor-pointer items-center justify-center rounded border border-white/10 text-neutral-300 hover:border-white/20 hover:text-white"
              phx-click={toggle_fullscreen(@terminal_id)}
              title="Toggle fullscreen"
              aria-label="Toggle fullscreen"
            >
              <span class="lucide-maximize-2 size-3.5" aria-hidden="true"></span>
              <span class="lucide-minimize-2 hidden size-3.5" aria-hidden="true"></span>
            </button>
          </div>
        </div>

        <div class="flex min-h-0 flex-1 p-3 pl-4">
          {render_slot(@inner_block)}
        </div>
      </div>
    </div>
    """
  end

  @doc """
  A message shown in the terminal's place, such as why there isn't one.
  """
  attr(:tone, :atom, default: :muted, values: [:muted, :alert])
  slot(:inner_block, required: true)

  def message(assigns) do
    ~H"""
    <div class={[
      "flex grow flex-col items-center justify-center gap-2 p-6 text-center font-mono text-ui",
      @tone == :muted && "text-neutral-400",
      @tone == :alert && "text-red-300"
    ]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  defp status_label(:connected), do: "Connected"
  defp status_label(:checking), do: "Checking…"
  defp status_label(:unavailable), do: "Not connected"

  # Fullscreen lifts the card over the whole window and names the device in
  # the toolbar, since the page header is hidden behind it.
  defp toggle_fullscreen(terminal_id) do
    %JS{}
    |> JS.toggle_class("relative fixed inset-0 z-50 rounded-card border", to: "#dropzone")
    |> JS.toggle_class("hidden", to: "##{terminal_id}-immersive")
    |> JS.toggle_class("hidden", to: "#fullscreen > span")
  end
end
