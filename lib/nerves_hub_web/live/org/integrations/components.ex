defmodule NervesHubWeb.Live.Org.Integrations.Components do
  @moduledoc """
  What the Integrations page's chat channels and webhooks share, so that the
  Slack, Teams and Discord sections (`SlackSection`, `ChatWebhookSection`)
  and the page's own webhooks read as two tables of one kind of thing: a
  row and its menu, the dialog it is added and edited in, and that dialog's
  fields.

  The functions after the components are for the forms behind those
  dialogs, which all take a set of products and a set of events the same
  way.
  """
  use NervesHubWeb, :component

  alias NervesHub.Integrations.ChannelEvents
  alias NervesHub.Webhooks.Events
  alias NervesHubWeb.CoreComponents
  alias Phoenix.HTML.Form
  alias Phoenix.HTML.FormField
  alias Phoenix.LiveView.JS

  @doc """
  A service's mark: Slack's, a stand-in for Microsoft Teams' and Discord's,
  or the webhook glyph. `class` sizes it.
  """
  attr(:service, :atom, required: true, values: [:slack, :teams, :discord, :webhook])
  attr(:class, :any, default: "size-3.75")

  def service_logo(%{service: :slack} = assigns) do
    ~H"""
    <svg viewBox="0 0 24 24" class={["shrink-0", @class]} aria-hidden="true">
      <path
        d="M5.042 15.165a2.528 2.528 0 0 1-2.52 2.523A2.528 2.528 0 0 1 0 15.165a2.527 2.527 0 0 1 2.522-2.52h2.52v2.52zM6.313 15.165a2.527 2.527 0 0 1 2.521-2.52 2.527 2.527 0 0 1 2.521 2.52v6.313A2.528 2.528 0 0 1 8.834 24a2.528 2.528 0 0 1-2.521-2.522v-6.313z"
        fill="#E01E5A"
      />
      <path
        d="M8.834 5.042a2.528 2.528 0 0 1-2.521-2.52A2.528 2.528 0 0 1 8.834 0a2.528 2.528 0 0 1 2.521 2.522v2.52H8.834zM8.834 6.313a2.528 2.528 0 0 1 2.521 2.521 2.528 2.528 0 0 1-2.521 2.521H2.522A2.528 2.528 0 0 1 0 8.834a2.528 2.528 0 0 1 2.522-2.521h6.312z"
        fill="#36C5F0"
      />
      <path
        d="M18.956 8.834a2.528 2.528 0 0 1 2.522-2.521A2.528 2.528 0 0 1 24 8.834a2.528 2.528 0 0 1-2.522 2.521h-2.522V8.834zM17.688 8.834a2.528 2.528 0 0 1-2.523 2.521 2.527 2.527 0 0 1-2.52-2.521V2.522A2.527 2.527 0 0 1 15.165 0a2.528 2.528 0 0 1 2.523 2.522v6.312z"
        fill="#2EB67D"
      />
      <path
        d="M15.165 18.956a2.528 2.528 0 0 1 2.523 2.522A2.528 2.528 0 0 1 15.165 24a2.527 2.527 0 0 1-2.52-2.522v-2.522h2.52zM15.165 17.688a2.527 2.527 0 0 1-2.52-2.523 2.526 2.526 0 0 1 2.52-2.52h6.313A2.527 2.527 0 0 1 24 15.165a2.528 2.528 0 0 1-2.522 2.523h-6.313z"
        fill="#ECB22E"
      />
    </svg>
    """
  end

  def service_logo(%{service: :teams} = assigns) do
    ~H"""
    <svg viewBox="0 0 24 24" class={["shrink-0", @class]} aria-hidden="true">
      <circle cx="19" cy="6.5" r="3.5" fill="#7B83EB" />
      <rect x="0.5" y="5" width="16" height="15" rx="3" fill="#4B53BC" />
      <path d="M4.5 9.5h8M8.5 9.5v7" fill="none" stroke="#FFFFFF" stroke-width="2.2" stroke-linecap="round" />
    </svg>
    """
  end

  def service_logo(%{service: :discord} = assigns) do
    ~H"""
    <svg viewBox="0 0 24 24" class={["shrink-0", @class]} aria-hidden="true">
      <rect x="0.5" y="0.5" width="23" height="23" rx="6" fill="#5865F2" />
      <path
        d="M6.6 7.9c1.6-.8 3.3-1.2 5.4-1.2s3.8.4 5.4 1.2c1.1 1.9 1.7 4 1.6 6.4-1.3 1-2.7 1.6-4.1 1.9l-.8-1.3c-.7.2-1.4.3-2.1.3s-1.4-.1-2.1-.3l-.8 1.3c-1.4-.3-2.8-.9-4.1-1.9-.1-2.4.5-4.5 1.6-6.4z"
        fill="#FFFFFF"
      />
      <circle cx="9.6" cy="11.9" r="1.3" fill="#5865F2" />
      <circle cx="14.4" cy="11.9" r="1.3" fill="#5865F2" />
    </svg>
    """
  end

  def service_logo(%{service: :webhook} = assigns) do
    ~H"""
    <span class={["lucide-webhook text-content-muted", @class]} aria-hidden="true"></span>
    """
  end

  @doc "The header row of a table of integrations, naming its first column."
  attr(:label, :string, required: true)

  def table_header(assigns) do
    ~H"""
    <div role="row" class="flex h-9 items-center gap-4 rounded-t-lg bg-surface px-4 md:px-5">
      <span role="columnheader" class="flex-1 text-[11px]/3.5 font-medium tracking-[0.06em] text-content-faint uppercase">{@label}</span>
      <span role="columnheader" class="hidden w-37.5 shrink-0 text-[11px]/3.5 font-medium tracking-[0.06em] text-content-faint uppercase md:block">
        Products
      </span>
      <span role="columnheader" class="hidden w-57.5 shrink-0 text-[11px]/3.5 font-medium tracking-[0.06em] text-content-faint uppercase md:block">
        Events
      </span>
      <span class="w-7 shrink-0" aria-hidden="true"></span>
    </div>
    """
  end

  @doc """
  One integration in a table: its mark, name, state and what it is, then the
  products and events it gets, then its menu.

  `products` is `:all`, or the names of the products it is limited to.
  `events` are the names of its events, which the Events column shortens to
  what fits and a count of the rest. A row without a `menu` keeps the menu's
  column, so its cells line up with the rows that have one.
  """
  attr(:id, :string, required: true)
  attr(:service, :atom, required: true)
  attr(:name, :string, required: true)
  attr(:status, :atom, required: true, values: [:on, :failing, :off])
  attr(:products, :any, required: true)
  attr(:events, :list, required: true)

  slot(:subline, required: true, doc: "what it is and where it posts, under the name")
  slot(:problem, doc: "why it is off, or what went wrong, in red under the subline")
  slot(:menu, doc: "the `menu_item/1`s of its ⋯ menu")

  def integration_row(assigns) do
    assigns = assign(assigns, :shown_events, shown_events(assigns.events))

    ~H"""
    <div role="row" id={@id} class="flex items-start gap-4 border-t border-line-subtle px-4 py-3.5 md:items-center md:px-5">
      <div role="cell" class="flex min-w-0 flex-1 items-start gap-3">
        <span class="flex size-7.5 shrink-0 items-center justify-center rounded-md bg-surface-muted">
          <.service_logo service={@service} />
        </span>
        <div class="flex min-w-0 flex-1 flex-col gap-1">
          <div class="flex flex-wrap items-center gap-x-2 gap-y-1">
            <h3 class="text-sm/4.5 font-medium wrap-break-word text-content-strong">{@name}</h3>
            <.status_chip status={@status} />
          </div>
          <div :for={subline <- @subline} class="truncate text-xs text-content-muted">{render_slot(subline)}</div>
          <p :for={problem <- @problem} class="pt-0.5 text-xs text-alert-content">{render_slot(problem)}</p>
          <p class="text-xs text-content-faint md:hidden">{products_text(@products)} · {events_count(@events)}</p>
        </div>
      </div>

      <div role="cell" class="hidden w-37.5 shrink-0 items-center gap-1.5 md:flex">
        <span class={["truncate text-[13px]/4", if(@products == [], do: "text-content-faint", else: "text-content-body")]}>
          {products_first(@products)}
        </span>
        <.more_chip :if={is_list(@products) && length(@products) > 1} count={length(@products) - 1} />
      </div>

      <div role="cell" class="hidden w-57.5 shrink-0 items-center gap-1.5 md:flex" title={Enum.join(@events, ", ")}>
        <span class="truncate text-[13px]/4 text-content-body">{Enum.join(@shown_events, ", ")}</span>
        <.more_chip :if={length(@events) > length(@shown_events)} count={length(@events) - length(@shown_events)} />
      </div>

      <div role="cell" class="relative w-7 shrink-0">
        {render_slot(@menu)}
      </div>
    </div>
    """
  end

  attr(:count, :integer, required: true)

  defp more_chip(assigns) do
    ~H"""
    <span class="flex h-4.5 shrink-0 items-center rounded bg-surface-muted px-1.5 text-[11px]/3.5 font-medium text-content-muted">
      +{@count}
    </span>
    """
  end

  @doc "An integration's state, when it is not simply on: Failing or Off."
  attr(:status, :atom, required: true, values: [:on, :failing, :off])

  def status_chip(%{status: :on} = assigns), do: ~H""

  def status_chip(%{status: :failing} = assigns) do
    ~H"""
    <span class="inline-flex h-4.5 items-center gap-1 rounded bg-alert-soft px-1.5 text-[11px]/3.5 font-medium text-alert-content">
      <span class="lucide-circle-exclamation-point--bold size-3" aria-hidden="true"></span> Failing
    </span>
    """
  end

  def status_chip(%{status: :off} = assigns) do
    ~H"""
    <span class="inline-flex h-4.5 items-center rounded bg-surface-muted px-1.5 text-[11px]/3.5 font-medium text-content-muted">Off</span>
    """
  end

  @doc """
  A row's ⋯ menu: the button that opens it, and the `menu_item/1`s and
  `menu_divider/1`s in it. `id` is the row's.
  """
  attr(:id, :string, required: true)
  attr(:label, :string, required: true, doc: "names the button, such as \"Actions for #fleet\"")
  slot(:inner_block, required: true)

  def row_menu(assigns) do
    ~H"""
    <button
      type="button"
      id={"#{@id}-menu-toggle"}
      phx-click={toggle_menu(@id)}
      aria-haspopup="menu"
      aria-label={@label}
      class="flex size-7 items-center justify-center rounded text-content-muted hover:cursor-pointer hover:bg-surface-muted hover:text-content-strong"
    >
      <span class="lucide-ellipsis size-4" aria-hidden="true"></span>
    </button>
    <div id={"#{@id}-menu"} class="hidden" phx-click-away={hide_menu(@id)} phx-window-keydown={hide_menu(@id)} phx-key="escape">
      <div role="menu" class="absolute top-8 right-0 z-30 flex w-58 flex-col rounded-md border border-line-default bg-surface-overlay p-1 shadow-overlay">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @doc "An item in a row's menu. `danger` colours it for removing something."
  attr(:icon, :string, required: true, doc: "a `lucide-*` class")
  attr(:danger, :boolean, default: false)
  attr(:rest, :global, include: ~w(disabled))
  slot(:inner_block, required: true)

  def menu_item(assigns) do
    ~H"""
    <button
      type="button"
      role="menuitem"
      class={[
        "flex h-8 shrink-0 items-center gap-2 rounded px-2 text-left text-[13px]/4 enabled:hover:cursor-pointer disabled:text-content-faint",
        if(@danger, do: "text-alert-content enabled:hover:bg-alert-soft", else: "text-content-body enabled:hover:bg-surface-muted")
      ]}
      {@rest}
    >
      <span class={[@icon, "size-3.5 shrink-0", !@danger && "text-content-muted"]} aria-hidden="true"></span>
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc "A line between groups of items in a menu."
  def menu_divider(assigns) do
    ~H"""
    <div class="my-1 h-px shrink-0 bg-line-subtle" aria-hidden="true"></div>
    """
  end

  @doc """
  An item of the Add integration menu: a service's mark, what it adds, and a
  line under it, such as the Slack workspace a channel is added in.
  """
  attr(:service, :atom, default: nil)
  attr(:icon, :string, default: nil, doc: "a `lucide-*` class, for an item without a service")
  attr(:detail, :string, default: nil)
  attr(:type, :string, default: "button")
  attr(:rest, :global, include: ~w(disabled))
  slot(:inner_block, required: true)

  def add_menu_item(assigns) do
    ~H"""
    <button
      type={@type}
      role="menuitem"
      class="flex w-full items-center gap-2.5 rounded p-2 text-left enabled:hover:cursor-pointer enabled:hover:bg-surface-muted disabled:opacity-60"
      {@rest}
    >
      <.service_logo :if={@service} service={@service} class="size-4" />
      <span :if={@icon} class={[@icon, "size-4 shrink-0 text-content-muted"]} aria-hidden="true"></span>
      <span class="flex min-w-0 flex-col gap-px">
        <span class="text-[13px]/4 text-content-body">{render_slot(@inner_block)}</span>
        <span :if={@detail} class="text-xs text-content-faint">{@detail}</span>
      </span>
    </button>
    """
  end

  @doc """
  A dialog an integration is added or edited in. The content is the dialog's
  form, laid out with `dialog_body/1` and `dialog_footer/1`.

  It opens when it is rendered and closes when it is removed, so the
  LiveView or component behind it shows it while it has a form open.
  `on_cancel` runs on Escape, a click outside, the close button and Cancel,
  and should close that form. It uses the core modal's ids, so
  `CoreComponents.show_modal/2` and `hide_modal/2` drive it.
  """
  attr(:id, :string, required: true)
  attr(:service, :atom, required: true)
  attr(:title, :string, required: true)
  attr(:on_cancel, JS, required: true)
  slot(:inner_block, required: true)

  def dialog(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={CoreComponents.show_modal(@id)}
      phx-remove={CoreComponents.hide_modal(@id)}
      data-cancel={JS.exec(@on_cancel, "phx-remove")}
      class="absolute z-50 hidden"
    >
      <div id={"#{@id}-bg"} class="fixed inset-0 bg-backdrop transition-opacity" aria-hidden="true" />
      <div class="fixed inset-0 overflow-y-auto" role="dialog" aria-modal="true" aria-labelledby={"#{@id}-title"} tabindex="0">
        <div class="flex min-h-full items-start justify-center px-4 py-8 sm:py-14">
          <.focus_wrap
            id={"#{@id}-container"}
            phx-window-keydown={JS.exec("data-cancel", to: "##{@id}")}
            phx-key="escape"
            phx-click-away={JS.exec("data-cancel", to: "##{@id}")}
            class="relative hidden w-full max-w-150 rounded-[10px] border border-line-default bg-surface-raised shadow-overlay transition"
          >
            <div class="flex items-center gap-3 border-b border-line-subtle px-5 pt-5 pb-4 sm:px-6">
              <span class="flex size-8 shrink-0 items-center justify-center rounded-lg bg-surface-muted">
                <.service_logo service={@service} class="size-4.25" />
              </span>
              <h2 id={"#{@id}-title"} class="min-w-0 flex-1 text-base/5.5 font-semibold wrap-break-word text-content-strong">{@title}</h2>
              <button
                type="button"
                phx-click={JS.exec("data-cancel", to: "##{@id}")}
                aria-label="Close"
                class="flex size-7 shrink-0 items-center justify-center rounded text-content-muted hover:cursor-pointer hover:bg-surface-muted hover:text-content-strong"
              >
                <span class="lucide-x size-4.5" aria-hidden="true"></span>
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

  @doc "A dialog's fields."
  slot(:inner_block, required: true)

  def dialog_body(assigns) do
    ~H"""
    <div class="flex flex-col gap-5 p-5 sm:px-6">
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc "A dialog's Cancel button and, in `inner_block`, its submit button. `dialog` is the dialog's id."
  attr(:dialog, :string, required: true)
  slot(:inner_block, required: true)

  def dialog_footer(assigns) do
    ~H"""
    <div class="flex items-center justify-end gap-2 rounded-b-[10px] border-t border-line-subtle bg-surface px-5 py-3.5 sm:px-6">
      <.button type="button" phx-click={JS.exec("data-cancel", to: "##{@dialog}")}>Cancel</.button>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Numbered steps to follow somewhere else, such as making a webhook in a
  chat service, before filling in a dialog.
  """
  attr(:title, :string, required: true)
  slot(:step, required: true)

  def steps(assigns) do
    ~H"""
    <div class="flex flex-col gap-2 rounded-md border border-line-subtle bg-surface px-4 py-3.5">
      <div class="text-xs font-semibold text-content-body">{@title}</div>
      <ol class="flex flex-col gap-2">
        <li :for={{step, number} <- Enum.with_index(@step, 1)} class="flex items-start gap-2.5 text-[13px]/4.5 text-content-muted">
          <span class="w-4 shrink-0 font-mono text-xs/4.5 text-content-faint" aria-hidden="true">{number}</span>
          <span>{render_slot(step)}</span>
        </li>
      </ol>
    </div>
    """
  end

  @doc """
  A text field in a dialog. `value` replaces the field's own, for a field
  whose saved value is never put back in the page. Errors show once the field
  has been used, as `CoreComponents.input/1`'s do.
  """
  attr(:field, FormField, required: true)
  attr(:label, :string, required: true)
  attr(:type, :string, default: "text")
  attr(:value, :any)
  attr(:mono, :boolean, default: false)
  attr(:rest, :global, include: ~w(autocomplete placeholder))
  slot(:hint)

  def text_field(assigns) do
    field = assigns.field
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns =
      assigns
      |> assign(:errors, Enum.map(errors, &CoreComponents.translate_error/1))
      |> assign_new(:value, fn -> field.value end)

    ~H"""
    <div class="flex flex-col gap-1.5">
      <label for={@field.id} class="text-[13px]/4 font-medium text-content-body">{@label}</label>
      <input
        type={@type}
        id={@field.id}
        name={@field.name}
        value={Form.normalize_value(@type, @value)}
        aria-describedby={@hint != [] && "#{@field.id}-hint"}
        class={[
          "h-9 w-full rounded-md border bg-surface-raised px-2.5 text-content-strong placeholder:text-content-faint focus:ring-3 focus:outline-none",
          if(@mono, do: "font-mono text-xs", else: "text-[13px]"),
          if(@errors == [], do: "border-line-strong focus:border-primary focus:ring-primary/20", else: "border-alert focus:ring-alert/20")
        ]}
        {@rest}
      />
      <div :for={hint <- @hint} id={"#{@field.id}-hint"} class="flex items-start gap-1.5 text-xs text-content-faint">
        {render_slot(hint)}
      </div>
      <CoreComponents.error :for={message <- @errors}>{message}</CoreComponents.error>
    </div>
    """
  end

  @doc """
  The products a form's integration gets events from: every product, which
  takes in products added later, or only the ones ticked. Its inputs are the
  form's `all_products` and `products`, and `id` prefixes their ids.
  """
  attr(:form, Form, required: true)
  attr(:id, :string, required: true)
  attr(:products, :list, required: true)

  def products_field(assigns) do
    assigns =
      assigns
      |> assign(:all?, all_products?(assigns.form))
      |> assign(:selected, selected_products(assigns.form))

    ~H"""
    <div class="flex flex-col gap-2" role="group" aria-labelledby={"#{@id}-products-label"}>
      <span id={"#{@id}-products-label"} class="text-[13px]/4 font-medium text-content-body">Products</span>
      <div class="flex gap-0.5 self-start rounded-md bg-surface-muted p-0.75">
        <label
          :for={{value, label} <- [{"true", "Every product"}, {"false", "Only some"}]}
          for={"#{@id}-all-products-#{value}"}
          class={[
            "flex h-7 items-center rounded px-3 text-[13px]/4 font-medium text-content-muted hover:cursor-pointer hover:text-content-strong",
            "has-checked:bg-surface-raised has-checked:text-content-strong has-checked:shadow-control",
            "has-focus-visible:outline-2 has-focus-visible:outline-focus-ring"
          ]}
        >
          <input
            type="radio"
            id={"#{@id}-all-products-#{value}"}
            name={@form[:all_products].name}
            value={value}
            checked={to_string(@all?) == value}
            class="sr-only"
          />
          {label}
        </label>
      </div>
      <p :if={@all?} class="text-xs text-content-faint">Includes products added later.</p>

      <input type="hidden" name={"#{@form.name}[products][]"} value="" />
      <div :if={!@all?} class="flex flex-col gap-2 rounded-md border border-line-default px-4 py-3.5">
        <label :for={product <- @products} for={"#{@id}-product-#{product.id}"} class="flex items-center gap-2 hover:cursor-pointer">
          <input
            type="checkbox"
            id={"#{@id}-product-#{product.id}"}
            name={"#{@form.name}[products][]"}
            value={product.name}
            checked={MapSet.member?(@selected, product.name)}
            class={checkbox_class()}
          />
          <span class="text-[13px]/4 text-content-body">{product.name}</span>
        </label>
        <p :if={@products == []} class="text-[13px] text-content-muted">This organization has no products yet.</p>
      </div>

      <CoreComponents.error :for={message <- checkbox_errors(@form, :products)}>{message}</CoreComponents.error>
    </div>
    """
  end

  @doc """
  The events a form's integration gets, ticked from `columns`: two lists of
  groups (`{group, [%{value: value, label: label, description: description}]}`),
  side by side once there is room. Its inputs are the form's `events`, and
  `id` prefixes their ids.
  """
  attr(:form, Form, required: true)
  attr(:id, :string, required: true)
  attr(:columns, :list, required: true)

  def events_field(assigns) do
    values = for column <- assigns.columns, {_group, events} <- column, event <- events, do: event.value
    selected = assigns.form[:events].value || []

    assigns =
      assigns
      |> assign(:selected, selected)
      |> assign(:total, length(values))
      |> assign(:count, Enum.count(values, &(&1 in selected)))

    ~H"""
    <div class="flex flex-col gap-2.5">
      <div class="flex items-baseline justify-between gap-3">
        <span id={"#{@id}-events-label"} class="text-[13px]/4 font-medium text-content-body">Events</span>
        <span class="text-xs text-content-faint">{@count} of {@total}</span>
      </div>
      <input type="hidden" name={"#{@form.name}[events][]"} value="" />
      <div role="group" aria-labelledby={"#{@id}-events-label"} class="grid gap-x-6 gap-y-3.5 rounded-md border border-line-default px-4 py-3.5 sm:grid-cols-2">
        <div :for={column <- @columns} class="flex flex-col gap-3.5">
          <div :for={{group, events} <- column} class="flex flex-col gap-2">
            <div class="text-[11px]/3.5 font-medium tracking-[0.06em] text-content-faint uppercase">{group}</div>
            <label :for={event <- events} for={"#{@id}-event-#{event.value}"} title={event.description} class="flex items-center gap-2 hover:cursor-pointer">
              <input
                type="checkbox"
                id={"#{@id}-event-#{event.value}"}
                name={"#{@form.name}[events][]"}
                value={event.value}
                checked={event.value in @selected}
                class={checkbox_class()}
              />
              <span class="text-[13px]/4 text-content-body">{event.label}</span>
            </label>
          </div>
        </div>
      </div>
      <CoreComponents.error :for={message <- checkbox_errors(@form, :events)}>{message}</CoreComponents.error>
    </div>
    """
  end

  defp checkbox_class() do
    "size-4 shrink-0 rounded-sm border-line-strong bg-surface-raised checked:border-transparent checked:bg-primary light:checked:bg-indigo-600 focus:ring-0 focus:ring-offset-0 focus-visible:ring-2 focus-visible:ring-focus-ring"
  end

  @doc """
  Opens or closes the menu of the row with this id, the way the device
  page's update-mode menu works.
  """
  def toggle_menu(id) do
    JS.toggle(
      to: "##{id}-menu",
      in: {"ease-out duration-150", "opacity-0", "opacity-100"},
      out: {"ease-out duration-150", "opacity-100", "opacity-0"}
    )
  end

  @doc """
  Closes the menu of the row with this id. It only ever closes, so Escape and
  a click elsewhere cannot open it the way `toggle_menu/1` would.
  """
  def hide_menu(js \\ %JS{}, id) do
    JS.hide(js, to: "##{id}-menu", transition: {"ease-out duration-150", "opacity-100", "opacity-0"})
  end

  @doc """
  The chat channels' events, in the two columns `events_field/1` lists them
  in: the device events, errors and product notifications in one, and the
  rollout steps in the other.
  """
  @spec channel_event_columns() :: [[{String.t(), [map()]}]]
  def channel_event_columns() do
    events = Enum.map(ChannelEvents.all(), &%{value: &1.key, label: &1.label, description: &1.description})
    left = prefixed_groups(events, [{"Devices", "device."}, {"Errors", "error_group."}, {"Product", "product."}])
    right = prefixed_groups(events, [{"Rollouts", "deployment_group."}])

    # An event added under a new prefix is still offered, rather than left out.
    case events -- Enum.flat_map(left ++ right, &elem(&1, 1)) do
      [] -> [left, right]
      others -> [left, right ++ [{"Other", others}]]
    end
  end

  defp prefixed_groups(events, prefixes) do
    for {group, prefix} <- prefixes,
        matching = Enum.filter(events, &String.starts_with?(&1.value, prefix)),
        matching != [],
        do: {group, matching}
  end

  @doc """
  The webhooks' events, in the groups `NervesHub.Webhooks.Events` gives them,
  split into the two columns `events_field/1` lists them in where the
  columns come out closest in length, keeping the groups in order.
  """
  @spec webhook_event_columns() :: [[{String.t(), [map()]}]]
  def webhook_event_columns() do
    groups =
      for {group, events} <- Events.grouped() do
        {group, Enum.map(events, &%{value: &1.type, label: &1.label, description: &1.description})}
      end

    # A group's height is its heading and its events, so count the heading as one.
    height = fn groups -> Enum.sum_by(groups, fn {_group, events} -> length(events) + 1 end) end

    split =
      Enum.min_by(0..length(groups), fn at ->
        {left, right} = Enum.split(groups, at)
        abs(height.(left) - height.(right))
      end)

    groups |> Enum.split(split) |> Tuple.to_list()
  end

  @doc "What a row's Products column says: `:all`, or the names of its products."
  @spec products_scope(map()) :: :all | [String.t()]
  def products_scope(%{all_products: true}), do: :all
  def products_scope(%{products: products}), do: Enum.map(products, & &1.name)

  @doc "Whether the form's integration takes in every product."
  @spec all_products?(Form.t()) :: boolean()
  def all_products?(form), do: Form.normalize_value("checkbox", form[:all_products].value)

  @doc """
  The products the form has ticked, by name, as its changeset holds them:
  products, or changesets for them once put on the integration.
  """
  @spec selected_products(Form.t()) :: MapSet.t(String.t())
  def selected_products(form) do
    form.source
    |> Ecto.Changeset.get_field(:products, [])
    |> MapSet.new(& &1.name)
  end

  @doc """
  The errors on a group of checkboxes, held back until somebody has ticked a
  box or submitted, the way `CoreComponents.input/1` holds back its own, so a
  form does not open by complaining.
  """
  @spec checkbox_errors(Form.t(), atom()) :: [String.t()]
  def checkbox_errors(form, field) do
    if Phoenix.Component.used_input?(form[field]) do
      Enum.map(form[field].errors, &CoreComponents.translate_error/1)
    else
      []
    end
  end

  @doc """
  A form's params without the blank its event and product checkboxes post
  alongside the ticked ones. The blank is there so that unticking every box
  still sends the field, and the changeset can say one is needed.
  """
  @spec form_params(map()) :: map()
  def form_params(params) do
    params
    |> Map.update("events", [], &drop_blank/1)
    |> Map.update("products", [], &drop_blank/1)
  end

  defp drop_blank(values), do: Enum.reject(List.wrap(values), &(&1 == ""))

  defp products_first(:all), do: "Every product"
  defp products_first([]), do: "No products"
  defp products_first([first | _rest]), do: first

  defp products_text(:all), do: "Every product"
  defp products_text([]), do: "No products"
  defp products_text([only]), do: only
  defp products_text([first | rest]), do: "#{first} +#{length(rest)}"

  defp events_count([_event]), do: "1 event"
  defp events_count(events), do: "#{length(events)} events"

  # As many event names as fit the Events column, at least one, and the rest
  # left to the "+N" after them.
  @events_column_characters 36

  defp shown_events([]), do: []

  defp shown_events([first | rest]) do
    {shown, _length} =
      Enum.reduce_while(rest, {[first], String.length(first)}, fn event, {shown, length} ->
        length = length + 2 + String.length(event)

        if length <= @events_column_characters,
          do: {:cont, {[event | shown], length}},
          else: {:halt, {shown, length}}
      end)

    Enum.reverse(shown)
  end
end
