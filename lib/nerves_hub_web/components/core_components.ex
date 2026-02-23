defmodule NervesHubWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as modals, tables, and
  forms. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The default components use Tailwind CSS, a utility-first CSS framework.
  See the [Tailwind CSS documentation](https://tailwindcss.com) to learn
  how to customize them or feel free to swap in another framework altogether.

  Icons are provided by [heroicons](https://heroicons.com). See `icon/1` for usage.
  """
  use Phoenix.Component, global_prefixes: ~w(js-)
  use Gettext, backend: NervesHubWeb.Gettext

  import NervesHubWeb.Components.Icons

  alias Phoenix.HTML.Form
  alias Phoenix.HTML.FormField
  alias Phoenix.LiveView.JS
  alias Phoenix.LiveView.LiveStream

  @doc """
  Renders the application logo. If `LOGO_URL` is configured, renders an `<img>` tag
  pointing to that URL. Otherwise renders the default NervesHub SVG logo.

  ## Attributes

    * `class` - Additional CSS classes for the logo element.
  """
  attr(:class, :string, default: nil)

  def logo(assigns) do
    assigns = assign(assigns, :logo_url, Application.get_env(:nerves_hub, :logo_url))

    ~H"""
    <%= if @logo_url do %>
      <img src={@logo_url} alt="Logo" class={@class} />
    <% else %>
      <svg class={@class} width="111" height="24" viewBox="0 0 111 24" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path
          d="M27.6721 0.0260367C28.4368 0.0260367 29.0567 0.656731 29.0567 1.43473V22.571C29.0567 23.349 28.4368 23.9797 27.6721 23.9797H22.1135L22.1163 23.9915C21.8164 23.9877 21.5258 23.8847 21.2885 23.698L7.79999 13.4673C7.44479 13.1961 7.23799 12.7687 7.24316 12.3169V11.7299C7.24264 11.2 7.53439 10.7146 7.99832 10.4736C8.46224 10.2327 9.01983 10.277 9.44133 10.5883L22.2779 20.053C22.5149 20.2264 22.7994 20.3198 23.0913 20.3201H24.0692C24.4367 20.3208 24.7893 20.1727 25.0491 19.9083C25.309 19.644 25.4546 19.2852 25.4538 18.9114V5.09734C25.4546 4.72349 25.309 4.36473 25.0491 4.10038C24.7893 3.83603 24.4367 3.68786 24.0692 3.68865H23.0365C22.6691 3.68943 22.3164 3.54126 22.0566 3.27691C21.7968 3.01256 21.6511 2.6538 21.6519 2.27995V1.43473C21.6519 0.656731 22.2718 0.0260367 23.0365 0.0260367H27.6721ZM39.0606 15.3192V18.6267H41.1404V15.3192H43.3356V23.9797H41.1404V20.5402H39.0606V23.9797H36.8654V15.3192H39.0606ZM53.1836 15.3192V21.9782C53.188 22.0406 53.2376 22.0898 53.299 22.0927H54.9C54.9692 22.0995 55.0309 22.0485 55.0385 21.9782V15.3192H57.2337V22.9907C57.2383 23.2524 57.139 23.5049 56.9582 23.6911C56.7773 23.8773 56.5303 23.9814 56.2731 23.9798H51.9606C51.4248 23.9781 50.9913 23.5358 50.9913 22.9907V15.3192H53.1836ZM70.94 15.602C71.157 15.8087 71.2771 16.0998 71.2702 16.4021V18.3273C71.2702 18.9143 70.8923 19.4836 70.1163 19.6744C70.8981 19.8681 71.3394 20.4052 71.3394 20.9833V22.8704C71.3552 23.1771 71.2386 23.4756 71.0202 23.6876C70.8018 23.8997 70.5033 24.0042 70.2029 23.9739L64.8894 23.9797V15.3192H70.1336C70.4298 15.2924 70.7231 15.3952 70.94 15.602ZM6.9721 0.00549316C7.2721 0.00908025 7.56276 0.112117 7.79999 0.298972L21.2885 10.5326C21.6429 10.8026 21.8479 11.2296 21.8394 11.6801V12.267C21.8392 12.7959 21.5479 13.2802 21.085 13.5209C20.6221 13.7616 20.0657 13.7183 19.6442 13.4086L6.81345 3.95278C6.5773 3.77729 6.29242 3.68274 5.99999 3.68278H5.01345C4.64573 3.68278 4.29311 3.83159 4.03336 4.09641C3.77361 4.36123 3.62807 4.72029 3.62883 5.09441V18.8996C3.62883 19.6776 4.24875 20.3083 5.01345 20.3083H6.05768C6.42514 20.3075 6.77777 20.4557 7.0376 20.7201C7.29743 20.9844 7.44306 21.3432 7.4423 21.717V22.5652C7.44309 22.9411 7.29587 23.3016 7.03354 23.5663C6.7712 23.831 6.41559 23.9778 6.04614 23.9739H1.41345C0.648746 23.9739 0.0288204 23.3432 0.0288204 22.5652V1.43473C0.0272982 1.06011 0.172499 0.70029 0.432332 0.434838C0.692164 0.169385 1.04522 0.0201639 1.41345 0.0201672H6.9721V0.00549316ZM69.0462 20.4257H67.0788V22.3363H69.0462C69.0806 22.3389 69.1144 22.3262 69.1388 22.3014C69.1632 22.2765 69.1757 22.2421 69.1731 22.2071V20.5666C69.1763 20.5303 69.1644 20.4944 69.1402 20.4676C69.1161 20.4408 69.0819 20.4256 69.0462 20.4257ZM69.0462 17.036H67.0788V18.8351H69.0462C69.1356 18.8351 69.1731 18.7705 69.1731 18.6913V17.1798C69.1763 17.1433 69.1644 17.1071 69.1404 17.0798C69.1163 17.0526 69.0822 17.0367 69.0462 17.036ZM109.399 2.96962V4.83028H106.321C106.286 4.831 106.252 4.84646 106.228 4.87308C106.204 4.89969 106.192 4.93513 106.194 4.97115V6.24191C106.202 6.30744 106.256 6.35679 106.321 6.35636H108.516C108.785 6.34175 109.047 6.44413 109.237 6.63792C109.427 6.8317 109.527 7.09857 109.512 7.3718V10.6177C109.526 10.8904 109.426 11.1565 109.236 11.3496C109.07 11.5186 108.849 11.6178 108.616 11.6302L104.002 11.6302V9.75778H107.192C107.279 9.75778 107.331 9.70495 107.331 9.64332V8.3843C107.331 8.31973 107.279 8.26984 107.192 8.26984H104.997C104.729 8.28446 104.466 8.18207 104.277 7.98829C104.11 7.81872 104.013 7.59321 104.002 7.35644L104.002 3.98506C103.987 3.71183 104.087 3.44496 104.277 3.25118C104.443 3.08161 104.664 2.98203 104.897 2.96958L109.399 2.96962ZM38.8846 2.96962L41.4317 7.74158V2.96962H43.4481V11.6302H41.3683L38.8846 6.86995V11.6302H36.8654V2.96962H38.8846ZM56.7894 2.96962V4.83028H53.4086V6.34462H56.3365V8.19354H53.4086V9.75778H56.7894V11.6302H51.2279V2.96962H56.7894ZM69.6144 2.96962C70.1433 2.96962 70.5721 3.40585 70.5721 3.94397V7.90886C70.5644 8.44418 70.1406 8.8767 69.6144 8.88615H69.551L70.5981 11.6302H68.4548L67.3933 8.88615H66.4615V11.6302H64.2692V2.96962H69.6144ZM79.4106 2.96962L80.5962 8.47528L82.0211 2.96962H84.1904L81.6548 11.6302H79.5375L77.0654 2.96962H79.4106ZM96.701 2.96962V4.83028H93.3202V6.34462H96.2452V8.19354H93.3202V9.75778H96.701V11.6302H91.1394V2.96962H96.701ZM68.276 4.82734H66.4615V7.13701H68.276C68.3349 7.12878 68.3818 7.08235 68.3913 7.02256V4.95647C68.3879 4.891 68.3397 4.83701 68.276 4.82734Z"
          fill="#FAFAFA"
        />
        <path
          d="M29.0567 1.43461C29.0567 0.656609 28.4368 0.0259147 27.6721 0.0259147H23.0365C22.2718 0.0259147 21.6519 0.656609 21.6519 1.43461V2.27983C21.6511 2.65368 21.7968 3.01244 22.0566 3.27679C22.3164 3.54114 22.6691 3.6893 23.0365 3.68852H24.0692C24.4367 3.68774 24.7893 3.83591 25.0491 4.10026C25.309 4.36461 25.4546 4.72337 25.4538 5.09722V18.9112C25.4546 19.2851 25.309 19.6439 25.0491 19.9082C24.7893 20.1726 24.4367 20.3207 24.0692 20.3199H23.0913C22.7994 20.3196 22.5149 20.2262 22.2779 20.0529L9.44133 10.5882C9.01983 10.2769 8.46224 10.2325 7.99832 10.4735C7.53439 10.7144 7.24264 11.1999 7.24316 11.7298V12.3168C7.23799 12.7686 7.44479 13.1959 7.79999 13.4672L21.2885 23.6979C21.5258 23.8845 21.8164 23.9876 22.1163 23.9914L22.1135 23.9796H27.6721C28.4368 23.9796 29.0567 23.3489 29.0567 22.5709V1.43461Z"
          fill="#6366F1"
        />
        <path
          d="M7.79999 0.298849C7.56276 0.111995 7.2721 0.00895818 6.9721 0.00537109V0.0200451H1.41345C1.04522 0.0200419 0.692164 0.169263 0.432332 0.434716C0.172499 0.700168 0.0272982 1.05999 0.0288204 1.43461V22.565C0.0288204 23.343 0.648746 23.9738 1.41345 23.9738H6.04614C6.41559 23.9777 6.7712 23.8309 7.03354 23.5662C7.29587 23.3015 7.44309 22.9409 7.4423 22.565V21.7169C7.44306 21.343 7.29743 20.9843 7.0376 20.7199C6.77777 20.4556 6.42514 20.3074 6.05768 20.3082H5.01345C4.24875 20.3082 3.62883 19.6775 3.62883 18.8995V5.09428C3.62807 4.72017 3.77361 4.36111 4.03336 4.09629C4.29311 3.83147 4.64573 3.68265 5.01345 3.68265H5.99999C6.29242 3.68261 6.5773 3.77717 6.81345 3.95265L19.6442 13.4085C20.0657 13.7182 20.6221 13.7615 21.085 13.5208C21.5479 13.28 21.8392 12.7958 21.8394 12.2669V11.6799C21.8479 11.2295 21.6429 10.8025 21.2885 10.5324L7.79999 0.298849Z"
          fill="#6366F1"
        />
      </svg>
    <% end %>
    """
  end

  @doc """
  Renders a modal.

  ## Examples

      <.modal id="confirm-modal">
        This is a modal.
      </.modal>

  JS commands may be passed to the `:on_cancel` to configure
  the closing/cancel event, for example:

      <.modal id="confirm" on_cancel={JS.navigate(~p"/posts")}>
        This is another modal.
      </.modal>

  """
  attr(:id, :string, required: true)
  attr(:show, :boolean, default: false)
  attr(:on_cancel, JS, default: %JS{})
  slot(:inner_block, required: true)

  def modal(assigns) do
    ~H"""
    <div id={@id} phx-mounted={@show && show_modal(@id)} phx-remove={hide_modal(@id)} data-cancel={JS.exec(@on_cancel, "phx-remove")} class="relative z-50 hidden">
      <div id={"#{@id}-bg"} class="bg-zinc-200/90 fixed inset-0 transition-opacity" aria-hidden="true" />
      <div class="fixed inset-0 overflow-y-auto" aria-labelledby={"#{@id}-title"} aria-describedby={"#{@id}-description"} role="dialog" aria-modal="true" tabindex="0">
        <div class="flex min-h-full items-center justify-center">
          <div class="w-full max-w-3xl p-4 sm:p-6 lg:py-8">
            <.focus_wrap
              id={"#{@id}-container"}
              phx-window-keydown={JS.exec("data-cancel", to: "##{@id}")}
              phx-key="escape"
              phx-click-away={JS.exec("data-cancel", to: "##{@id}")}
              class="shadow-zinc-700/10 ring-zinc-700/10 relative hidden rounded-2xl bg-zinc-900 p-4 shadow-lg ring-1 transition"
            >
              <div class="absolute top-6 right-5">
                <button phx-click={JS.exec("data-cancel", to: "##{@id}")} type="button" class="-m-3 flex-none p-3 opacity-20 hover:opacity-40" aria-label={gettext("close")}>
                  <.icon name="close" class="size-8 stroke-zinc-200" />
                </button>
              </div>
              <div id={"#{@id}-content"}>
                {render_slot(@inner_block)}
              </div>
            </.focus_wrap>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr(:id, :string, doc: "the optional id of flash container")
  attr(:flash, :map, default: %{}, doc: "the map of flash messages to display")
  attr(:title, :string, default: nil)
  attr(:kind, :atom, values: [:notice, :info, :error], doc: "used for styling and flash lookup")
  attr(:rest, :global, doc: "the arbitrary HTML attributes to add to the flash container")

  slot(:inner_block, doc: "the optional inner block that renders the flash message")

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class={[
        "fixed bottom-4 right-2 mr-2 w-80 sm:w-96 z-50 rounded-sm p-3 ring-1",
        @kind == :notice && "bg-indigo-50 text-indigo-800 ring-indigo-500 fill-indigo-900",
        @kind == :info && "bg-emerald-50 text-emerald-800 ring-emerald-500 fill-cyan-900",
        @kind == :error && "bg-rose-50 text-rose-900 shadow-md ring-rose-500 fill-rose-900"
      ]}
      {@rest}
    >
      <p :if={@title} class="flex items-center gap-1.5 text-sm font-semibold leading-6">
        {@title}
      </p>
      <p class="mt-1 text-sm leading-5">{msg}</p>
      <button type="button" class="group absolute top-1 right-1 p-2" aria-label={gettext("close")}>
        <.icon
          name="close"
          class={[
            @kind == :notice && "stroke-indigo-500",
            @kind == :info && "stroke-emerald-500",
            @kind == :error && "stroke-red-500",
            "opacity-40 group-hover:opacity-70"
          ]}
        />
      </button>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr(:flash, :map, required: true, doc: "the map of flash messages")
  attr(:id, :string, default: "flash-group", doc: "the optional id of flash container")

  def flash_group(assigns) do
    ~H"""
    <div id={@id}>
      <.flash kind={:notice} title={gettext("Info")} flash={@flash} phx-mounted={show("#flash-notice")} phx-hook="Flash" hidden />
      <.flash kind={:info} title={gettext("Success")} flash={@flash} phx-mounted={show("#flash-info")} phx-hook="Flash" hidden />
      <.flash kind={:error} title={gettext("Error")} flash={@flash} phx-mounted={show("#flash-error")} hidden />

      <.flash
        id="connection-status"
        kind={:error}
        title={gettext("Internet connection lost")}
        phx-disconnected={show("#connection-status")}
        js-hide={hide("#connection-status")}
        js-show={show("#connection-status")}
        hidden
      >
        {gettext("Attempting to reconnect...")}
      </.flash>
    </div>
    """
  end

  @doc """
  Renders a simple form.

  ## Examples

      <.simple_form for={@form} phx-change="validate" phx-submit="save">
        <.input field={@form[:email]} label="Email"/>
        <.input field={@form[:username]} label="Username" />
        <:actions>
          <.button>Save</.button>
        </:actions>
      </.simple_form>
  """
  attr(:for, :any, required: true, doc: "the data structure for the form")
  attr(:as, :any, default: nil, doc: "the server side parameter to collect all input under")

  attr(:rest, :global,
    include: ~w(autocomplete name rel action enctype method novalidate target multipart),
    doc: "the arbitrary HTML attributes to apply to the form tag"
  )

  slot(:inner_block, required: true)
  slot(:actions, doc: "the slot for form actions, such as a submit button")

  def simple_form(assigns) do
    ~H"""
    <.form :let={f} for={@for} as={@as} {@rest}>
      <div class="mt-10 space-y-8 bg-white">
        {render_slot(@inner_block, f)}
        <div :for={action <- @actions} class="mt-2 flex items-center justify-between gap-6">
          {render_slot(action, f)}
        </div>
      </div>
    </.form>
    """
  end

  @doc """
  Renders a button.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" class="ml-2">Send!</.button>
  """
  attr(:style, :string, default: "secondary")
  attr(:type, :string, default: "button")
  attr(:class, :string, default: nil)
  attr(:rest, :global, include: ~w(disabled form name value href navigate download patch))

  slot(:inner_block, required: true)

  def button(%{type: "link", style: "secondary"} = assigns) do
    ~H"""
    <.link
      class={[
        "phx-submit-loading:opacity-75 flex items-center justify-center px-3 py-1.5 gap-2 rounded",
        "bg-zinc-800 hover:bg-zinc-700 active:bg-indigo-500 disabled:bg-zinc-800",
        "border rounded border-zinc-600 active:border-indigo-500",
        "stroke-zinc-400 active:stroke-zinc-100 disabled:stroke-zinc-600",
        "text-sm font-medium text-zinc-300 hover:text-neutral-50 active:text-neutral-50 disabled:text-zinc-500",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  def button(%{type: "link", style: "danger"} = assigns) do
    ~H"""
    <.link
      class={[
        "flex items-center",
        "phx-submit-loading:opacity-75 flex px-3 py-1.5 gap-2 rounded",
        "bg-zinc-800 hover:bg-zinc-700 active:bg-zinc-600",
        "border rounded border-red-500",
        "stroke-red-500",
        "text-sm font-medium text-red-500",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  def button(%{style: "primary"} = assigns) do
    ~H"""
    <button
      type={@type}
      class={[
        "phx-submit-loading:opacity-75 flex px-3 py-1.5 gap-2 rounded",
        "bg-indigo-500 hover:bg-indigo-400 active:bg-indigo-600 disabled:bg-zinc-800",
        "disabled:bg-zinc-800 disabled:border disabled:rounded disabled:border-zinc-600",
        "stroke-zinc-50 disabled:stroke-zinc-500",
        "text-sm font-medium text-zinc-50 disabled:text-zinc-500",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  def button(%{style: "secondary"} = assigns) do
    ~H"""
    <button
      type={@type}
      class={[
        "phx-submit-loading:opacity-75 flex px-3 py-1.5 gap-2 rounded",
        "bg-zinc-800 hover:bg-zinc-700 active:bg-indigo-500 disabled:bg-zinc-800",
        "border rounded border-zinc-600 active:border-indigo-500",
        "stroke-zinc-400 active:stroke-zinc-100 disabled:stroke-zinc-600",
        "text-sm font-medium text-zinc-300 hover:text-neutral-50 active:text-neutral-50 disabled:text-zinc-500",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  def button(%{style: "danger"} = assigns) do
    ~H"""
    <button
      type={@type}
      class={[
        "phx-submit-loading:opacity-75 flex px-3 py-1.5 gap-2 rounded",
        "bg-zinc-800 hover:bg-zinc-700 active:bg-zinc-600",
        "border rounded border-red-500",
        "stroke-red-500",
        "text-sm font-medium text-red-500",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  def button(assigns) do
    ~H"""
    <button
      type={@type}
      class={[
        "phx-submit-loading:opacity-75 rounded-lg bg-zinc-900 hover:bg-zinc-700 py-2 px-3",
        "text-sm font-semibold leading-6 text-white active:text-white/80",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information.

  ## Examples

      <.input field={@form[:email]} type="email" />
      <.input name="my-input" errors={["oh no!"]} />
  """
  attr(:id, :any, default: nil)
  attr(:name, :any)
  attr(:label, :string, default: nil)
  attr(:hide_label, :boolean, default: false)
  attr(:value, :any)

  attr(:type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file hidden month number password
               range radio search select tel text textarea time url week)
  )

  attr(:field, FormField, doc: "a form field struct retrieved from the form, for example: @form[:email]")

  attr(:errors, :list, default: [])
  attr(:checked, :boolean, doc: "the checked flag for checkbox inputs")
  attr(:prompt, :string, default: nil, doc: "the prompt for select inputs")
  attr(:options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2")
  attr(:multiple, :boolean, default: false, doc: "the multiple flag for select inputs")

  attr(:hint, :string, default: nil, doc: "a hint to be displayed next to the label")

  attr(:rest, :global, include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step))

  slot(:inner_block)
  slot(:rich_hint)

  def input(%{field: %FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error/1))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div phx-feedback-for={@name}>
      <span class="flex items-center gap-4 text-sm font-medium leading-6 text-zinc-300">
        <input type="hidden" name={@name} value="false" />
        <input type="checkbox" id={@name} name={@name} value="true" checked={@checked} class="rounded border-zinc-700 text-zinc-400 focus:ring-0 checked:bg-indigo-500" {@rest} />
        <label for={@name}>{@label}</label>
      </span>
      <div :if={assigns[:hint] || assigns[:rich_hint]} class="text-xs text-zinc-400">
        {assigns[:hint] || render_slot(assigns[:rich_hint])}
      </div>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name} class="flex flex-col gap-2">
      <.label for={@id} hide={@hide_label}>{@label}</.label>
      <select
        id={@id}
        name={@name}
        class="mt-2 px-2 py-1 block w-full rounded border border-zinc-600 ext-zinc-400 bg-zinc-900 shadow-sm focus:border-zinc-400 focus:ring-0 sm:text-sm"
        multiple={@multiple}
        {@rest}
      >
        <option :if={@prompt} value="">{@prompt}</option>
        {Phoenix.HTML.Form.options_for_select(@options, @value)}
      </select>
      <div :if={assigns[:hint] || assigns[:rich_hint]} class="text-xs text-zinc-400">
        {assigns[:hint] || render_slot(assigns[:rich_hint])}
      </div>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <.label for={@id}>{@label}</.label>
      <textarea
        id={@id}
        name={@name}
        class={[
          "mt-2 block w-full rounded text-zinc-400 bg-zinc-900 focus:ring-0 sm:text-sm sm:leading-6",
          "min-h-[6rem] phx-no-feedback:border-zinc-600 phx-no-feedback:focus:border-zinc-700",
          @errors == [] && "border-zinc-600 focus:border-zinc-700",
          @errors != [] && "border-red-500 focus:border-red-500"
        ]}
        {@rest}
      ><%= Phoenix.HTML.Form.normalize_value("textarea", @value) %></textarea>
      <div :if={assigns[:hint] || assigns[:rich_hint]} class="flex flex-col gap-1 text-xs text-zinc-400 pt-1">
        {assigns[:hint] || render_slot(assigns[:rich_hint])}
      </div>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "number"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <span class="flex items-end">
        <.label for={@id}>{@label}</.label>
      </span>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class={[
          "mt-2 py-1.5 px-2 block w-full rounded text-zinc-400 bg-zinc-900 focus:ring-0 sm:text-sm",
          "phx-no-feedback:border-zinc-600 phx-no-feedback:focus:border-zinc-700",
          @errors == [] && "border-zinc-600 focus:border-zinc-700",
          @errors != [] && "border-red-500 focus:border-red-500"
        ]}
        {@rest}
      />
      <div :if={assigns[:hint] || assigns[:rich_hint]} class="flex flex-col gap-1 text-xs text-zinc-400 pt-1">
        {assigns[:hint] || render_slot(assigns[:rich_hint])}
      </div>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <.label for={@id}>{@label}</.label>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class={[
          "mt-2 py-1.5 px-2 block w-full rounded text-zinc-400 bg-zinc-900 focus:ring-0 sm:text-sm",
          "phx-no-feedback:border-zinc-600 phx-no-feedback:focus:border-zinc-700",
          @errors == [] && "border-zinc-600 focus:border-zinc-700",
          @errors != [] && "border-red-500 focus:border-red-500"
        ]}
        {@rest}
      />
      <p :if={assigns[:hint]} class="mt-1 text-xs text-zinc-400">{@hint}</p>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  @doc """
  Renders a label.
  """
  attr(:for, :string, default: nil)
  attr(:hide, :boolean, default: false)
  slot(:inner_block, required: true)

  def label(assigns) do
    ~H"""
    <label for={@for} class={["block text-sm font-medium text-zinc-300", @hide && "hidden"]}>
      {render_slot(@inner_block)}
    </label>
    """
  end

  # TODO: can be removed when we remove our use of Phoenix.HTML.Form
  def core_label(assigns), do: label(assigns)

  @doc """
  Generates a generic error message.
  """
  slot(:inner_block, required: true)

  def error(assigns) do
    ~H"""
    <p class="mt-1 flex gap-2 text-sm leading-6 text-red-500 phx-no-feedback:hidden">
      <svg class="mt-0.5 size-5 stroke-red-500 flex-none" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path d="M12 5V13M12 19.001V19" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" />
      </svg>

      <span class="error-text">{render_slot(@inner_block)}</span>
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  attr(:class, :string, default: nil)

  slot(:inner_block, required: true)
  slot(:subtitle)
  slot(:actions)

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", @class]}>
      <div>
        <h1 class="text-lg font-semibold leading-8 text-zinc-800">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="mt-2 text-sm leading-6 text-zinc-600">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc ~S"""
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id"><%= user.id %></:col>
        <:col :let={user} label="username"><%= user.username %></:col>
      </.table>
  """
  attr(:id, :string, required: true)
  attr(:rows, :list, required: true)
  attr(:row_id, :any, default: nil, doc: "the function for generating the row id")
  attr(:row_click, :any, default: nil, doc: "the function for handling phx-click on each row")

  attr(:row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"
  )

  slot :col, required: true do
    attr(:label, :string)
  end

  slot(:action, doc: "the slot for showing user actions in the last table column")

  def table(assigns) do
    assigns =
      with %{rows: %LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <div class="overflow-y-auto px-4 sm:overflow-visible sm:px-0">
      <table class="w-[40rem] mt-11 sm:w-full">
        <thead class="text-sm text-left leading-6 text-zinc-500">
          <tr>
            <th :for={col <- @col} class="p-0 pb-4 pr-6 font-normal">{col[:label]}</th>
            <th :if={@action != []} class="relative p-0 pb-4">
              <span class="sr-only">{gettext("Actions")}</span>
            </th>
          </tr>
        </thead>
        <tbody id={@id} phx-update={match?(%Phoenix.LiveView.LiveStream{}, @rows) && "stream"} class="relative divide-y divide-zinc-100 border-t border-zinc-200 text-sm leading-6 text-zinc-700">
          <tr :for={row <- @rows} id={@row_id && @row_id.(row)} class="group hover:bg-zinc-50">
            <td :for={{col, i} <- Enum.with_index(@col)} phx-click={@row_click && @row_click.(row)} class={["relative p-0", @row_click && "hover:cursor-pointer"]}>
              <div class="block py-4 pr-6">
                <span class="absolute -inset-y-px right-0 -left-4 group-hover:bg-zinc-50 sm:rounded-l-xl" />
                <span class={["relative", i == 0 && "font-semibold text-zinc-900"]}>
                  {render_slot(col, @row_item.(row))}
                </span>
              </div>
            </td>
            <td :if={@action != []} class="relative w-14 p-0">
              <div class="relative whitespace-nowrap py-4 text-right text-sm font-medium">
                <span class="absolute -inset-y-px -right-4 left-0 group-hover:bg-zinc-50 sm:rounded-r-xl" />
                <span :for={action <- @action} class="relative ml-4 font-semibold leading-6 text-zinc-900 hover:text-zinc-700">
                  {render_slot(action, @row_item.(row))}
                </span>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title"><%= @post.title %></:item>
        <:item title="Views"><%= @post.views %></:item>
      </.list>
  """
  slot :item, required: true do
    attr(:title, :string, required: true)
  end

  def list(assigns) do
    ~H"""
    <div class="mt-14">
      <dl class="-my-4 divide-y divide-zinc-100">
        <div :for={item <- @item} class="flex gap-4 py-4 text-sm leading-6 sm:gap-8">
          <dt class="w-1/4 flex-none text-zinc-500">{item.title}</dt>
          <dd class="text-zinc-700">{render_slot(item)}</dd>
        </div>
      </dl>
    </div>
    """
  end

  @doc """
  Renders a back navigation link.

  ## Examples

      <.back navigate={~p"/posts"}>Back to posts</.back>
  """
  attr(:navigate, :any, required: true)
  slot(:inner_block, required: true)

  def back(assigns) do
    ~H"""
    <div class="mt-16">
      <.link navigate={@navigate} class="text-sm font-semibold leading-6 text-zinc-900 hover:text-zinc-700">
        <.icon name="hero-arrow-left-solid" class="h-3 w-3" />
        {render_slot(@inner_block)}
      </.link>
    </div>
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      transition:
        {"transition-all transform ease-out duration-300", "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all transform ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  def show_modal(js \\ %JS{}, id) when is_binary(id) do
    js
    |> JS.show(to: "##{id}")
    |> JS.show(
      to: "##{id}-bg",
      transition: {"transition-all transform ease-out duration-300", "opacity-0", "opacity-100"}
    )
    |> show("##{id}-container")
    |> JS.add_class("overflow-hidden", to: "body")
    |> JS.focus_first(to: "##{id}-content")
  end

  def hide_modal(js \\ %JS{}, id) do
    js
    |> JS.hide(
      to: "##{id}-bg",
      transition: {"transition-all transform ease-in duration-200", "opacity-100", "opacity-0"}
    )
    |> hide("##{id}-container")
    |> JS.hide(to: "##{id}", transition: {"block", "block", "hidden"})
    |> JS.remove_class("overflow-hidden", to: "body")
    |> JS.pop_focus()
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(NervesHubWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(NervesHubWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
