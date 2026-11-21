defmodule NervesHubWeb.Components.Dialog do
  @moduledoc """
  The design system's dialogs: one for asking before an action, and one for a
  form that adds or edits something.

  `confirm/1` asks before something that changes every device, sends firmware
  to more of them, or can't be undone: a title, a sentence or two, and Cancel
  beside the action under a divider. A short form can use it too, as creating
  an API key does.

  `form_dialog/1` holds a longer form, such as a release or an integration,
  with `form_body/1` for its fields and `form_footer/1` for its buttons.

  On a phone both are a sheet from the bottom, their buttons stacked across
  it, the action first.
  """
  use NervesHubWeb, :component

  alias NervesHubWeb.CoreComponents
  alias Phoenix.LiveView.JS

  @doc """
  Asks before an action. It opens when it's rendered, so a LiveView shows it
  while an assign says what it's asking about. Cancel, Escape and a click
  outside all run `on_cancel`, which should clear that assign. It uses the
  core modal's ids, so `CoreComponents.show_modal/2` and `hide_modal/2` open
  and close it.

  The title is `title`, or the `heading` slot when part of it is set in mono,
  such as a firmware version. The `subtitle` slot goes right under the title,
  for what pins down exactly what the dialog is about, such as the UUID of
  the firmware it deletes. A dialog holding a list is `wide`, and so are the
  other dialogs on its page. The `note` slot holds a line such as what a new
  API key was given.

  One showing a secret only once sets `dismissible` to false. Nothing in it
  clips, so a popover inside it, such as the API key role picker, can hang
  past the footer.
  """
  attr(:id, :string, required: true)
  attr(:title, :string, default: nil)
  attr(:on_cancel, JS, required: true)
  attr(:wide, :boolean, default: false, doc: "480px from `sm` up rather than 440px")

  attr(:dismissible, :boolean,
    default: true,
    doc: "whether Cancel, Escape and a click outside close it; without them, only its own buttons do"
  )

  slot(:heading, doc: "the title with markup, in place of `title`")
  slot(:subtitle, doc: "a line under the title naming exactly what it's about")
  slot(:inner_block, required: true)
  slot(:note, doc: "a line at the start of the footer, opposite the buttons")
  slot(:actions, doc: "the buttons after Cancel, the one that acts last")

  def confirm(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={CoreComponents.show_modal(@id)}
      phx-remove={CoreComponents.hide_modal(@id)}
      data-cancel={JS.exec(@on_cancel, "phx-remove")}
      class="absolute z-50 hidden"
    >
      <div id={"#{@id}-bg"} class="fixed inset-0 bg-backdrop transition-opacity" aria-hidden="true" />
      <div
        class="fixed inset-0 overflow-y-auto"
        role="dialog"
        aria-modal="true"
        aria-labelledby={"#{@id}-title"}
        aria-describedby={"#{@id}-description"}
        tabindex="0"
      >
        <div class="flex min-h-full items-end justify-center sm:items-center sm:p-4">
          <.focus_wrap
            id={"#{@id}-container"}
            phx-window-keydown={@dismissible && JS.exec("data-cancel", to: "##{@id}")}
            phx-key={@dismissible && "escape"}
            phx-click-away={@dismissible && JS.exec("data-cancel", to: "##{@id}")}
            class={[
              "relative hidden w-full rounded-t-xl border-t border-line-default bg-surface-overlay shadow-overlay transition sm:rounded-md sm:border",
              if(@wide, do: "sm:max-w-120", else: "sm:max-w-110")
            ]}
          >
            <div class="flex justify-center pt-2 pb-1 sm:hidden" aria-hidden="true">
              <span class="h-1 w-9 rounded-full bg-line-default"></span>
            </div>
            <div id={"#{@id}-content"}>
              <div class="flex flex-col gap-1.5 px-4 pt-3 pb-4 sm:gap-2 sm:px-5 sm:pt-5">
                <div class="flex flex-col gap-1">
                  <h2 id={"#{@id}-title"} class="text-card-title font-semibold wrap-break-word text-content-strong">
                    {if @heading == [], do: @title, else: render_slot(@heading)}
                  </h2>
                  <p :if={@subtitle != []} id={"#{@id}-subtitle"} class="text-xs/4 wrap-break-word text-content-faint">
                    {render_slot(@subtitle)}
                  </p>
                </div>
                <div id={"#{@id}-description"} class="flex flex-col gap-3 text-ui/5 text-content-muted">
                  {render_slot(@inner_block)}
                </div>
              </div>
              <div class="flex items-center gap-2 border-line-subtle max-sm:flex-col max-sm:items-stretch max-sm:px-4 max-sm:pb-6 sm:border-t sm:px-5 sm:py-3">
                <p :if={@note != []} id={"#{@id}-note"} class="text-xs/4 text-content-muted">{render_slot(@note)}</p>
                <div class="ml-auto flex justify-end gap-2 max-sm:ml-0 max-sm:flex-col-reverse max-sm:*:h-10 max-sm:*:rounded-md max-sm:*:text-sm">
                  <.button :if={@dismissible} phx-click={JS.exec("data-cancel", to: "##{@id}")}>Cancel</.button>
                  {render_slot(@actions)}
                </div>
              </div>
            </div>
          </.focus_wrap>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  A dialog a form adds or edits something in, such as a release or an
  integration. Like `confirm/1`, it opens when it's rendered, and Escape, a
  click outside, the close button and Cancel all run `on_cancel`, which should
  close the form. It uses the core modal's ids, so
  `CoreComponents.show_modal/2` and `hide_modal/2` drive it.

  It hangs from the top of the page and grows downward, 560px wide, or 600px
  when `wide`, as the integration dialogs are for their two columns of events.
  On a phone it's a sheet from the bottom.

  The content is the form, with its fields in `form_body/1` and its buttons in
  `form_footer/1`. The `icon` slot puts a tile before the title, such as an
  integration's service logo, and the `subtitle` slot a line under it.
  """
  attr(:id, :string, required: true)
  attr(:title, :string, required: true)
  attr(:on_cancel, JS, required: true)
  attr(:wide, :boolean, default: false, doc: "600px from `sm` up rather than 560px")

  slot(:icon, doc: "a tile before the title, such as an integration's service logo")
  slot(:subtitle, doc: "a line under the title")
  slot(:inner_block, required: true)

  def form_dialog(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={CoreComponents.show_modal(@id)}
      phx-remove={CoreComponents.hide_modal(@id)}
      data-cancel={JS.exec(@on_cancel, "phx-remove")}
      class="absolute z-50 hidden"
    >
      <div id={"#{@id}-bg"} class="fixed inset-0 bg-backdrop transition-opacity" aria-hidden="true" />
      <div
        class="fixed inset-0 overflow-y-auto"
        role="dialog"
        aria-modal="true"
        aria-labelledby={"#{@id}-title"}
        aria-describedby={@subtitle != [] && "#{@id}-subtitle"}
        tabindex="0"
      >
        <div class="flex min-h-full items-end justify-center pt-12 sm:items-start sm:px-4 sm:py-14">
          <.focus_wrap
            id={"#{@id}-container"}
            phx-window-keydown={JS.exec("data-cancel", to: "##{@id}")}
            phx-key="escape"
            phx-click-away={JS.exec("data-cancel", to: "##{@id}")}
            class={[
              "relative hidden w-full rounded-t-xl border-t border-line-default bg-surface-overlay shadow-overlay transition sm:rounded-md sm:border",
              if(@wide, do: "sm:max-w-150", else: "sm:max-w-140")
            ]}
          >
            <div class="flex justify-center pt-2 pb-1 sm:hidden" aria-hidden="true">
              <span class="h-1 w-9 rounded-full bg-line-default"></span>
            </div>
            <div class={[
              "flex gap-3 border-b border-line-subtle px-4 pt-3 pb-4 sm:px-5 sm:pt-5",
              if(@icon == [], do: "items-start", else: "items-center")
            ]}>
              <span :for={icon <- @icon} class="flex size-8 shrink-0 items-center justify-center rounded-lg bg-surface-muted">
                {render_slot(icon)}
              </span>
              <div class="flex min-w-0 flex-1 flex-col gap-1.5 sm:gap-2">
                <h2 id={"#{@id}-title"} class="text-card-title font-semibold wrap-break-word text-content-strong">{@title}</h2>
                <p :if={@subtitle != []} id={"#{@id}-subtitle"} class="text-ui/5 text-content-muted">{render_slot(@subtitle)}</p>
              </div>
              <button
                type="button"
                phx-click={JS.exec("data-cancel", to: "##{@id}")}
                aria-label="Close"
                class={[
                  "-mr-1.5 flex size-7 shrink-0 cursor-pointer items-center justify-center rounded text-content-faint hover:bg-surface-muted hover:text-content-strong focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus-ring",
                  @icon == [] && "-mt-0.5"
                ]}
              >
                <span class="lucide-x--bold size-3.5" aria-hidden="true"></span>
              </button>
            </div>
            <div id={"#{@id}-content"}>
              {render_slot(@inner_block)}
            </div>
          </.focus_wrap>
        </div>
      </div>
    </div>
    """
  end

  @doc "A form dialog's fields, 20px apart."
  slot(:inner_block, required: true)

  def form_body(assigns) do
    ~H"""
    <div class="flex flex-col gap-5 p-5 max-sm:px-4">
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  A form dialog's buttons: Cancel, then the form's own in `inner_block`, the
  one that acts last. `dialog` is the dialog's id. The `start` slot holds an
  action at the start of the row, such as removing a release's connecting
  code, which sets its own `mr-auto`. On a phone they stack across the sheet,
  the action first.
  """
  attr(:dialog, :string, required: true)
  slot(:start, doc: "an action at the start of the row, which sets its own `mr-auto`")
  slot(:inner_block, required: true)

  def form_footer(assigns) do
    ~H"""
    <div class={[
      "flex items-center justify-end gap-2 border-t border-line-subtle px-5 py-3",
      "max-sm:flex-col-reverse max-sm:items-stretch max-sm:px-4 max-sm:pb-6 max-sm:*:h-10 max-sm:*:rounded-md max-sm:*:text-sm"
    ]}>
      {render_slot(@start)}
      <.button phx-click={JS.exec("data-cancel", to: "##{@dialog}")}>Cancel</.button>
      {render_slot(@inner_block)}
    </div>
    """
  end
end
