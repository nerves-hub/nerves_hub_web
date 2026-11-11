defmodule NervesHubWeb.Components.ErrorPage do
  @moduledoc """
  The 400, 404 and 500 pages: the perfboard backdrop of the auth pages, a
  drawing of the fault, and the message under it.

  Error pages render without a layout, from both endpoints
  (`NervesHubWeb.ErrorHTML` and `NervesHubWeb.ErrorDeviceHTML`), so `page/1`
  is the whole document and takes its asset paths from the caller. The
  helpers read what they need from the `conn` Phoenix passes when it renders
  an error, and fall back when there isn't one (`render_to_string/4` in tests).
  """
  use NervesHubWeb, :component

  alias Phoenix.HTML.Engine

  @doc """
  Renders a complete error document.

  ## Examples

      <ErrorPage.page title="Page not found" code="404" label="Not found" css_path={...} js_path={...}>
        <:drawing><ErrorPage.footprint ref="U404" note="DNP" /></:drawing>
        <:headline>That page doesn't exist.</:headline>
        Some explanation.
        <:actions>...</:actions>
      </ErrorPage.page>
  """
  attr(:title, :string, required: true, doc: "the start of the tab title")
  attr(:code, :string, required: true, doc: "the status code, shown above the headline")
  attr(:label, :string, required: true, doc: "what the code means, shown after it")
  attr(:tone, :atom, default: :notice, values: [:notice, :alert])
  attr(:css_path, :string, required: true)
  attr(:js_path, :string, required: true)

  slot(:drawing, required: true)
  slot(:headline, required: true)
  slot(:inner_block, required: true, doc: "the explanation under the headline")
  slot(:actions, required: true)
  slot(:note, doc: "a line under the actions")

  def page(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en" class="h-full bg-surface" data-theme="dark">
      <head>
        <meta charset="utf-8" />
        <meta http-equiv="X-UA-Compatible" content="IE=edge" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Phoenix.Controller.get_csrf_token()} />

        <link rel="icon" type="image/png" href="/images/favicon-96x96.png" sizes="96x96" />
        <link rel="icon" type="image/svg+xml" href="/images/favicon.svg" />
        <link rel="shortcut icon" href="/images/favicon.ico" />

        <title>{@title} · {platform_name()}</title>
        <link rel="stylesheet" href={@css_path} />
        <script defer phx-track-static type="text/javascript" src={@js_path}>
        </script>
        <script type="text/javascript">
          // Match the theme the user picked in the app (see the root layout).
          if (
            localStorage.theme === "light" ||
            (localStorage.theme === "system" && window.matchMedia("(prefers-color-scheme: light)").matches)
          ) {
            document.documentElement.setAttribute("data-theme", "light");
          }

          // There is no LiveView here, so the page's buttons are wired by hand.
          document.addEventListener("click", (event) => {
            if (event.target.closest("[data-history-back]")) return history.back();
            if (event.target.closest("[data-reload]")) return location.reload();

            const copy = event.target.closest("[data-copy]");
            if (!copy) return;

            // The clipboard API is missing on plain HTTP and can be refused, so
            // fall back to selecting the ID for a manual copy.
            const written = navigator.clipboard ? navigator.clipboard.writeText(copy.dataset.copy) : Promise.reject();
            written
              .then(() => { copy.textContent = "Copied"; })
              .catch(() => { getSelection().selectAllChildren(document.getElementById("request-id")); });
          });
        </script>
      </head>

      <body class="h-full">
        <div class="flex min-h-full flex-col items-center perfboard px-4 pt-12 pb-8">
          <a href="/" class="flex h-6 items-center">
            <.logo class="h-6" />
          </a>

          <main class="flex w-full max-w-170 flex-1 flex-col items-center justify-center gap-10 py-12 text-center">
            <div class="w-full max-w-105" aria-hidden="true">
              {render_slot(@drawing)}
            </div>

            <div class="flex flex-col items-center gap-3.5">
              <p class={[
                "font-mono text-xs/4 font-semibold tracking-[0.12em] uppercase",
                @tone == :notice && "text-primary light:text-indigo-600",
                @tone == :alert && "text-alert-content"
              ]}>
                {@code} · {@label}
              </p>
              <h1 class="text-3xl font-bold tracking-[-0.03em] text-balance text-content-strong sm:text-[2.5rem]/[2.875rem]">
                {render_slot(@headline)}
              </h1>
              <p class="max-w-125 text-base/6.5 text-content-muted">
                {render_slot(@inner_block)}
              </p>
            </div>

            <div class="flex flex-col items-center gap-5">
              <div class="flex flex-wrap items-center justify-center gap-3">
                {render_slot(@actions)}
              </div>
              <p :if={@note != []} class="text-sm text-content-muted">
                {render_slot(@note)}
              </p>
            </div>
          </main>
        </div>
      </body>
    </html>
    """
  end

  @doc """
  An empty chip footprint: pads with only the first one wired, and a dashed
  outline where the part should be. For "nothing is here".
  """
  attr(:ref, :string, required: true, doc: "the reference designator, e.g. U404")
  attr(:note, :string, required: true, doc: "the line under it, e.g. DNP (do not populate)")

  def footprint(assigns) do
    ~H"""
    <svg class="h-auto w-full" viewBox="0 0 420 184" fill="none">
      <g class="stroke-primary light:stroke-indigo-600" stroke-width="2">
        <path d="M0 34 H156" />
        <path d="M0 150 H156" />
        <rect x="156" y="18" width="18" height="32" rx="3" class="fill-surface" />
        <rect x="156" y="134" width="18" height="32" rx="3" class="fill-surface" />
      </g>
      <g class="stroke-line-default" stroke-width="2">
        <path d="M420 34 H264" />
        <path d="M420 150 H264" />
        <rect :for={x <- [186, 216, 246]} x={x} y="18" width="18" height="32" rx="3" class="fill-surface" />
        <rect :for={x <- [186, 216, 246]} x={x} y="134" width="18" height="32" rx="3" class="fill-surface" />
      </g>
      <rect x="132" y="56" width="156" height="72" rx="3" class="stroke-line-strong" stroke-width="1.5" stroke-dasharray="5 4" />
      <circle cx="146" cy="70" r="3" class="fill-line-strong" />
      <.labels ref={@ref} note={@note} y={90} />
    </svg>
    """
  end

  @doc """
  A blown fuse between a live trace and an idle one. For "it broke on our side".
  """
  attr(:ref, :string, required: true, doc: "the reference designator, e.g. F500")
  attr(:note, :string, required: true, doc: "the line under it, e.g. OPEN")

  def fuse(assigns) do
    ~H"""
    <svg class="h-auto w-full" viewBox="0 0 420 184" fill="none">
      <circle cx="210" cy="92" r="30" class="fill-alert/8" />
      <circle cx="210" cy="92" r="16" class="fill-alert/12" />
      <rect x="150" y="78" width="120" height="28" rx="14" class="stroke-line-strong" stroke-width="1.5" />
      <g stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <g class="stroke-primary light:stroke-indigo-600">
          <path d="M0 92 H122" />
          <path d="M150 92 H166 L174 82 L182 102 L190 84 L196 90" />
          <rect x="122" y="72" width="28" height="40" rx="3" class="fill-surface" />
        </g>
        <g class="stroke-line-default">
          <path d="M298 92 H420" />
          <path d="M224 96 L230 82 L238 102 L246 82 L254 92 H270" />
          <rect x="270" y="72" width="28" height="40" rx="3" class="fill-surface" />
        </g>
        <g class="stroke-alert">
          <path d="M210 66 V56" />
          <path d="M196 70 L189 63" />
          <path d="M224 70 L231 63" />
        </g>
      </g>
      <.labels ref={@ref} note={@note} y={148} />
    </svg>
    """
  end

  attr(:ref, :string, required: true)
  attr(:note, :string, required: true)
  attr(:y, :integer, required: true, doc: "the baseline of the reference designator")

  defp labels(assigns) do
    ~H"""
    <g class="font-mono" text-anchor="middle">
      <text x="210" y={@y} class="fill-content-strong text-[15px] font-semibold tracking-[0.04em]">
        {@ref}
      </text>
      <text x="210" y={@y + 17} class="fill-content-faint text-[11px] font-medium tracking-[0.14em]">
        {@note}
      </text>
    </g>
    """
  end

  @doc """
  A text link in the auth pages' style.
  """
  attr(:href, :string, required: true)
  attr(:rest, :global, include: ~w(target rel))
  slot(:inner_block, required: true)

  def text_link(assigns) do
    ~H"""
    <a href={@href} class="font-semibold whitespace-nowrap text-primary hover:text-primary-hover light:text-indigo-600 light:hover:text-indigo-500" {@rest}>
      {render_slot(@inner_block)}
    </a>
    """
  end

  @doc """
  A "Go back" button. Browsers have no history to go back to in a new tab, so
  it is only a hint there, never the only way out.
  """
  attr(:style, :string, default: "secondary")

  def back_button(assigns) do
    ~H"""
    <.button style={@style} data-history-back>Go back</.button>
    """
  end

  @doc """
  Shows the request ID support can find the failure by, with a button that
  copies it. Renders nothing when there is no ID.
  """
  attr(:id, :string, default: nil)

  def request_id(assigns) do
    ~H"""
    <span :if={@id}>
      Request ID <code id="request-id" class="font-mono text-ui font-medium break-all text-content-strong">{@id}</code>
      ·
      <button
        type="button"
        data-copy={@id}
        class="cursor-pointer font-semibold text-primary hover:text-primary-hover light:text-indigo-600 light:hover:text-indigo-500"
      >
        Copy
      </button>
    </span>
    """
  end

  @doc """
  The ID `Plug.RequestId` gave the failed request, or nil.
  """
  @spec request_id_of(Plug.Conn.t() | nil) :: String.t() | nil
  def request_id_of(%Plug.Conn{} = conn) do
    case Plug.Conn.get_resp_header(conn, "x-request-id") do
      [id | _] -> id
      [] -> Logger.metadata()[:request_id]
    end
  end

  def request_id_of(nil), do: nil

  @doc """
  The path the visitor asked for, or nil.
  """
  @spec path_of(Plug.Conn.t() | nil) :: String.t() | nil
  def path_of(%Plug.Conn{request_path: path}), do: path
  def path_of(nil), do: nil

  @doc """
  A path with a line-break opportunity after each slash, so a long one wraps
  between segments on a phone instead of mid-word.
  """
  @spec breakable_path(String.t()) :: Phoenix.HTML.safe()
  def breakable_path(path) do
    {:safe,
     path
     |> String.split("/")
     |> Enum.map(&Engine.html_escape/1)
     |> Enum.intersperse("/<wbr>")}
  end

  @doc """
  Whether reloading the page repeats the request harmlessly. Only GETs are:
  reloading anything else asks the browser to resubmit it.
  """
  @spec reloadable?(Plug.Conn.t() | nil) :: boolean()
  def reloadable?(%Plug.Conn{method: method}), do: method in ["GET", "HEAD"]
  def reloadable?(nil), do: false

  @doc """
  The instance's name, as used in page titles.
  """
  def platform_name(), do: Application.get_env(:nerves_hub, :web_title_suffix)

  @doc """
  The instance's status page (`STATUS_PAGE_URL`), or nil when it has none.
  """
  def status_page_url(), do: Application.get_env(:nerves_hub, :status_page_url)

  @doc """
  Where to report a broken link or a recurring error.
  """
  def issues_url(), do: "https://github.com/nerves-hub/nerves_hub_web/issues"
end
