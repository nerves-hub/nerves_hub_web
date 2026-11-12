defmodule NervesHubWeb.Components.DevicePage.TerminalFrame do
  @moduledoc """
  The card the Console and System Shell tabs draw their terminal in: a toolbar
  saying whether the session is live, then the terminal on a fixed dark
  background, which stays dark in light mode because xterm draws its own
  colours.

  The element IDs are looked up by the terminal hooks in `assets/js`:
  `dropzone` takes dropped files, `fullscreen` is listened to for refitting the
  terminal, and `option-as-meta` is revealed on a Mac.

  On a phone, typing fills the space the keyboard leaves with the frame, under
  a bar with a Done button and over a row of the keys a phone's keyboard lacks.
  `assets/js/helpers/terminalKeyboard.js` runs it, from the
  `data-terminal-frame`, `data-terminal-key` and `data-terminal-done`
  attributes.
  """

  use NervesHubWeb, :component

  alias Phoenix.LiveView.JS

  @terminal_background "background-color: rgb(14, 16, 25);"

  attr(:terminal_id, :string, required: true, doc: "the ID of the element the terminal hook draws in")
  attr(:status, :atom, required: true, values: [:connected, :checking, :unavailable])
  attr(:identifier, :string, required: true)
  attr(:name, :string, required: true, doc: "what the terminal is, such as \"Console\"")
  attr(:file_input, :string, default: nil, doc: "the ID of a file picker to send files with, on a phone")
  attr(:note, :string, default: nil, doc: "beside the status, such as who else sees the session")
  attr(:hint, :string, default: nil, doc: "at the end of the toolbar, before the controls")
  slot(:inner_block, required: true, doc: "the terminal, or a message in its place")

  def frame(assigns) do
    assigns = assign(assigns, :background, @terminal_background)

    ~H"""
    <%!-- On a phone the page scrolls, so the frame takes the height left under
          the top bar and the tabs. --%>
    <div class="flex size-full flex-col p-4 max-sm:h-[calc(100dvh-93px)] sm:p-6">
      <div
        id={if(@status == :connected, do: "dropzone", else: "terminal-frame")}
        data-terminal-frame
        class={[
          "relative flex min-h-0 flex-1 flex-col overflow-hidden rounded-card border border-line-default shadow-card",
          "terminal-typing:fixed terminal-typing:inset-x-0 terminal-typing:top-(--terminal-top) terminal-typing:z-50 terminal-typing:h-(--terminal-height) terminal-typing:rounded-none terminal-typing:border-0"
        ]}
        style={@background}
      >
        <div :if={@status == :connected} class="hidden h-14 shrink-0 items-center gap-2.5 border-b border-line-default bg-surface-raised pr-2 pl-4 terminal-typing:flex">
          <span class="size-2 shrink-0 rounded-full bg-success" aria-hidden="true"></span>
          <div class="flex min-w-0 flex-1 flex-col">
            <span class="truncate font-mono text-[0.9375rem]/5 font-semibold text-content-strong">{@identifier}</span>
            <span class="text-xs text-content-muted">{@name} · connected</span>
          </div>
          <button type="button" data-terminal-done class="flex h-11 cursor-pointer items-center px-2.5 text-base font-semibold text-primary">
            Done
          </button>
        </div>

        <div class="flex h-11 shrink-0 items-center gap-3 border-b border-white/10 px-3.5 text-xs text-neutral-400 max-sm:h-15 max-sm:gap-2 max-sm:pr-2.5 terminal-typing:hidden">
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
          <span :if={@note && @status == :connected} class="hidden min-w-0 truncate max-sm:inline md:inline">{@note}</span>
          <span :if={@hint && @status == :connected} class="ml-auto hidden truncate text-neutral-500 lg:inline">{@hint}</span>

          <div :if={@status == :connected} id="terminal-controls" phx-update="ignore" class={["flex items-center gap-2", if(@hint, do: "max-lg:ml-auto", else: "ml-auto")]}>
            <label
              class="hidden h-6.5 cursor-pointer items-center gap-1.5 rounded border border-white/10 px-2 text-neutral-300 hover:border-white/20 max-sm:hidden!"
              title="Send ⌥ (Option) to the device as Meta, for shortcuts such as M-b and M-f. Leave this off to type characters like [ ] { } | on non-US keyboard layouts."
            >
              <input type="checkbox" id="option-as-meta" class="size-3 rounded-sm border-white/30 bg-transparent text-primary checked:bg-primary focus:ring-0" />
              <span>⌥ as Meta</span>
            </label>
            <label
              :if={@file_input}
              for={@file_input}
              title="Send a file to the device"
              class="flex size-11 cursor-pointer items-center justify-center rounded-md border border-white/10 text-neutral-300 sm:hidden"
            >
              <span class="lucide-upload size-4.5" aria-hidden="true"></span>
              <span class="sr-only">Send a file to the device</span>
              <input type="file" id={@file_input} class="hidden" />
            </label>
            <button
              id="fullscreen"
              type="button"
              class="flex size-6.5 cursor-pointer items-center justify-center rounded border border-white/10 text-neutral-300 hover:border-white/20 hover:text-white max-sm:size-11 max-sm:rounded-md"
              phx-click={toggle_fullscreen(@terminal_id)}
              title="Toggle fullscreen"
              aria-label="Toggle fullscreen"
            >
              <span class="lucide-maximize-2 size-3.5 max-sm:size-4.5" aria-hidden="true"></span>
              <span class="lucide-minimize-2 hidden size-3.5 max-sm:size-4.5" aria-hidden="true"></span>
            </button>
          </div>
        </div>

        <div class="flex min-h-0 flex-1 p-3 pl-4">
          {render_slot(@inner_block)}
        </div>

        <%!-- Ignored by patches, so a pressed Ctrl stays pressed. --%>
        <div
          :if={@status == :connected}
          id={"#{@terminal_id}-keys"}
          phx-update="ignore"
          class="hidden shrink-0 grid-cols-7 gap-1.5 border-t border-line-default bg-surface-muted p-1.5 terminal-typing:grid"
        >
          <button
            :for={{key, label, icon} <- keys()}
            type="button"
            data-terminal-key={key}
            aria-pressed={if(key == "ctrl", do: "false")}
            aria-label={label}
            class="flex h-9 cursor-pointer items-center justify-center rounded-md bg-surface-raised text-sm font-medium text-content-strong shadow-xs aria-pressed:bg-primary aria-pressed:text-primary-content"
          >
            <span :if={icon} class={[icon, "size-4"]} aria-hidden="true"></span>
            <span :if={!icon} aria-hidden="true">{label}</span>
          </button>
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

  defp keys() do
    [
      {"esc", "Esc", nil},
      {"tab", "Tab", nil},
      {"ctrl", "Ctrl", nil},
      {"up", "Up", "lucide-chevron-up"},
      {"down", "Down", "lucide-chevron-down"},
      {"left", "Left", "lucide-chevron-left"},
      {"right", "Right", "lucide-chevron-right"}
    ]
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
