defmodule NervesHubWeb.Components.OtpInput do
  @moduledoc """
  A one-time code field drawn as a row of single-digit slots.

  The slots are only drawn. Typing goes into one real `<input>` laid over them,
  so pasting a whole code, the browser's one-time-code autofill and password
  managers work as they do on any field. Until `assets/js/otpInput.js` runs
  (or without JavaScript) the input shows as a plain text field and the slots
  stay hidden.

  On a page LiveView doesn't run, `otpInput.js` mounts every `[data-otp-input]`
  when the page loads. Inside a LiveView, set `hook` so it is mounted, and
  kept, through the `OtpInput` hook.
  """
  use Phoenix.Component

  attr(:id, :string, required: true, doc: "the id of the real input, for its label")
  attr(:name, :string, required: true)
  attr(:length, :integer, default: 6)
  attr(:invalid, :boolean, default: false, doc: "draws the slots in the alert colour and shakes them once")
  attr(:autosubmit, :boolean, default: false, doc: "submits the form once every slot is filled")
  attr(:hook, :boolean, default: false, doc: "set inside a LiveView")
  attr(:disabled, :boolean, default: false)
  attr(:autofocus, :boolean, default: false)
  attr(:rest, :global, include: ~w(aria-describedby required))

  def otp_input(assigns) do
    ~H"""
    <div
      id={"#{@id}_otp"}
      data-otp-input
      data-otp-autosubmit={to_string(@autosubmit)}
      data-otp-invalid={@invalid}
      phx-hook={@hook && "OtpInput"}
      class="group/otp relative mt-2"
    >
      <input
        type="text"
        id={@id}
        name={@name}
        value=""
        data-otp-field
        placeholder="000 000"
        autocomplete="one-time-code"
        autocapitalize="none"
        spellcheck="false"
        disabled={@disabled}
        autofocus={@autofocus}
        class={[
          "block h-13 w-full rounded bg-base-900 px-3 text-center font-mono text-2xl tracking-[0.18em] text-content-strong placeholder:text-content-faint focus:ring-2 disabled:cursor-not-allowed disabled:opacity-60",
          "group-data-otp-ready/otp:absolute group-data-otp-ready/otp:inset-0 group-data-otp-ready/otp:z-10 group-data-otp-ready/otp:h-full group-data-otp-ready/otp:cursor-text group-data-otp-ready/otp:opacity-0",
          !@invalid && "border-line-strong focus:ring-focus-ring",
          @invalid && "border-alert focus:ring-alert"
        ]}
        {@rest}
      />
      <div
        aria-hidden="true"
        class={[
          "pointer-events-none hidden items-center gap-2 group-data-otp-invalid/otp:animate-otp-shake group-data-otp-ready/otp:flex motion-reduce:animate-none",
          @disabled && "opacity-60"
        ]}
      >
        <%= for i <- 0..(@length - 1) do %>
          <span :if={i > 0 and i == div(@length, 2)} class="h-0.5 w-2.5 flex-none rounded-full bg-line-strong"></span>
          <div
            data-otp-slot
            class={[
              "group/slot relative flex h-13 min-w-0 flex-1 items-center justify-center rounded border border-line-strong bg-base-900 font-mono text-2xl font-medium text-content-strong transition-[border-color,box-shadow] duration-150",
              "data-otp-active:border-primary data-otp-active:ring-2 data-otp-active:ring-focus-ring data-otp-filled:border-content-muted",
              "group-data-otp-invalid/otp:border-alert group-data-otp-invalid/otp:data-otp-active:border-alert group-data-otp-invalid/otp:data-otp-active:ring-alert"
            ]}
          >
            <span data-otp-char class="group-data-otp-popped/slot:animate-otp-pop motion-reduce:animate-none"></span>
            <span data-otp-caret class="absolute hidden h-6 w-px animate-otp-blink bg-content-strong group-data-otp-caret-on/slot:block motion-reduce:animate-none"></span>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
