defmodule NervesHubWeb.Layouts do
  use NervesHubWeb, :html

  alias NervesHub.Accounts.Org
  alias NervesHubWeb.Components.Fleet
  alias NervesHubWeb.Components.Navigation
  alias NervesHubWeb.Components.Pager
  alias Phoenix.LiveView.JS

  defp toggle_user_menu(js \\ %JS{}) do
    JS.toggle(js,
      in: {"ease-out duration-150", "opacity-0", "opacity-100"},
      out: {"ease-out duration-150", "opacity-100", "opacity-0"},
      to: "#user-menu-container"
    )
  end

  # Only ever closes the menu - used for Escape and click-away so those never
  # open the menu (JS.toggle would), and are no-ops when it's already closed.
  defp hide_user_menu(js \\ %JS{}) do
    JS.hide(js,
      transition: {"ease-out duration-150", "opacity-100", "opacity-0"},
      to: "#user-menu-container"
    )
  end

  embed_templates("layouts/*")

  attr(:flash, :map, required: true)
  attr(:current_scope, :map, required: true)
  attr(:tab, :atom, required: true, doc: "the selected tab, the `sidebar_tab` the page sets")
  attr(:counts, :map, required: true, doc: "`@org_counts`, which `NervesHubWeb.Mounts.OrgCounts` assigns")
  slot(:actions, doc: "buttons at the right of the header, shown from md up")
  slot(:inner_block, required: true)

  @doc """
  An organization's pages: its name and counts in a header, a row of tabs
  for its sections, and the page centered under them.

  A page using it mounts `NervesHubWeb.Mounts.OrgCounts` for `@org_counts`,
  and heads its content with `org_heading/1`.
  """
  def org(assigns)

  attr(:title, :string, required: true)

  attr(:back, :string,
    default: nil,
    doc: "where the back arrow goes, for a page inside a tab rather than the tab itself"
  )

  attr(:back_label, :string, default: "Back")
  slot(:actions, doc: "buttons at the end of the heading")
  slot(:inner_block, doc: "a line under the title")

  @doc """
  The heading of an organization page's content, under its tabs. The tabs'
  header holds the organization's name as the page's h1, so this is an h2.
  """
  def org_heading(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center justify-between gap-x-4 gap-y-3">
      <div class="flex min-w-0 items-center gap-2">
        <.link
          :if={@back}
          navigate={@back}
          aria-label={@back_label}
          title={@back_label}
          class="-ml-2 flex size-8 shrink-0 items-center justify-center rounded text-content-muted hover:bg-surface-muted hover:text-content-strong"
        >
          <span class="lucide-arrow-left size-4" aria-hidden="true"></span>
        </.link>
        <div class="min-w-0">
          <h2 class="text-section-title wrap-anywhere text-content-strong">{@title}</h2>
          <p :if={@inner_block != []} class="text-sm text-content-muted">{render_slot(@inner_block)}</p>
        </div>
      </div>
      <div :if={@actions != []} class="flex shrink-0 flex-wrap items-center gap-2">
        {render_slot(@actions)}
      </div>
    </div>
    """
  end

  # "3 products · 1,204 devices · 5 members", or, before there's a product,
  # what to do about it. `Fleet.separated/1` puts the dots between.
  defp org_summary(%{products: 0} = counts) do
    ["No products yet", Fleet.count_noun(counts.members, "member", "members")]
  end

  defp org_summary(counts) do
    [
      Fleet.count_noun(counts.products, "product", "products"),
      Fleet.count_noun(counts.devices, "device", "devices"),
      Fleet.count_noun(counts.members, "member", "members")
    ]
  end

  # Each icon is spelled out in full, regular and bold, so Tailwind finds the
  # class names in this file.
  defp org_tabs(%Org{} = org, counts) do
    [
      %{
        key: :products,
        label: "Products",
        path: ~p"/org/#{org}",
        icon: "lucide-package",
        selected_icon: "lucide-package--bold",
        count: nil
      },
      %{
        key: :users,
        label: "Users",
        path: ~p"/org/#{org}/settings/users",
        icon: "lucide-users",
        selected_icon: "lucide-users--bold",
        count: counts.members
      },
      %{
        key: :signing_keys,
        label: "Signing keys",
        path: ~p"/org/#{org}/settings/keys",
        icon: "lucide-key-round",
        selected_icon: "lucide-key-round--bold",
        count: counts.signing_keys
      },
      %{
        key: :certificates,
        label: "Certificates",
        path: ~p"/org/#{org}/settings/certificates",
        icon: "lucide-shield-check",
        selected_icon: "lucide-shield-check--bold",
        count: counts.certificates
      },
      Navigation.org_iroh_endpoints_ui_enabled?() &&
        %{
          key: :iroh_endpoints,
          label: "Iroh endpoints",
          path: ~p"/org/#{org}/settings/iroh-endpoints",
          icon: "lucide-waypoints",
          selected_icon: "lucide-waypoints--bold",
          count: nil
        },
      %{
        key: :integrations,
        label: "Integrations",
        path: ~p"/org/#{org}/settings/integrations",
        icon: "lucide-webhook",
        selected_icon: "lucide-webhook--bold",
        count: nil
      },
      %{
        key: :settings,
        label: "Settings",
        path: ~p"/org/#{org}/settings",
        icon: "lucide-settings",
        selected_icon: "lucide-settings--bold",
        count: nil
      }
    ]
    |> Enum.filter(& &1)
  end

  @doc """
  How a tab links to its path.

  Tabs patch by default, which is what a page whose tabs are `live_action`s of
  one LiveView wants — the device and deployment group pages. A tab whose
  target is a *different* LiveView cannot be patched to, so it opts into
  `navigate` by setting `navigate: true` on the slot.
  """
  def tab_target(%{navigate: true} = nav), do: %{navigate: nav.path}
  def tab_target(nav), do: %{patch: nav.path}

  def toggle_product_picker(js \\ %JS{}) do
    JS.toggle(js,
      to: "#product-picker",
      in: {"ease-in duration-200", "opacity-0", "opacity-100"},
      out: {"ease-out duration-200", "opacity-100", "opacity-0"}
    )
  end

  def hide_product_picker(js \\ %JS{}) do
    JS.hide(js,
      to: "#product-picker",
      transition: {"ease-out duration-200", "opacity-100", "opacity-0"}
    )
  end

  def featurebase_sdk(%{current_scope: scope, app_id: app_id} = assigns) when is_nil(scope) or is_nil(app_id) do
    ~H"""
    """
  end

  def featurebase_sdk(%{current_scope: %{user: user}, app_id: app_id} = assigns) do
    claims = %{
      name: user.name,
      email: user.email,
      userId: Integer.to_string(user.id),
      createdAt: NaiveDateTime.to_string(user.inserted_at),
      theme: "light",
      language: "en"
    }

    case generate_token(claims) do
      {:ok, jwt} ->
        assigns = %{
          appId: app_id,
          featurebaseJwt: jwt
        }

        ~H"""
        <script>
          !(function(e,t){var a="featurebase-sdk";function n(){if(!t.getElementById(a)){var e=t.createElement("script");(e.id=a),(e.src="https://do.featurebase.app/js/sdk.js"),t.getElementsByTagName("script")[0].parentNode.insertBefore(e,t.getElementsByTagName("script")[0])}};"function"!=typeof e.Featurebase&&(e.Featurebase=function(){(e.Featurebase.q=e.Featurebase.q||[]).push(arguments)}),"complete"===t.readyState||"interactive"===t.readyState?n():t.addEventListener("DOMContentLoaded",n)})(window,document);
        </script>

        <script>
          Featurebase("boot", {
            appId: "<%= @appId %>",
            featurebaseJwt: "<%= @featurebaseJwt %>"
          });
        </script>
        """

      _ ->
        ~H"""
        """
    end
  end

  # An HS256 JWT carrying just `claims`, which is all Featurebase asks for.
  defp generate_token(claims) do
    case Application.get_env(:nerves_hub, :featurebase_signing_token) do
      key when is_binary(key) and key != "" ->
        signing_input = base64url(JSON.encode!(%{alg: "HS256", typ: "JWT"})) <> "." <> base64url(JSON.encode!(claims))
        signature = base64url(:crypto.mac(:hmac, :sha256, key, signing_input))

        {:ok, signing_input <> "." <> signature}

      _ ->
        :error
    end
  end

  defp base64url(data), do: Base.url_encode64(data, padding: false)
end
