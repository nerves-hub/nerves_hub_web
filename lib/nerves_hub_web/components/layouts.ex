defmodule NervesHubWeb.Layouts do
  use NervesHubWeb, :html

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

  defp generate_token(claims) do
    key = Application.get_env(:nerves_hub, :featurebase_signing_token)
    signer = Joken.Signer.create("HS256", key)

    Joken.generate_and_sign(%{}, claims, signer)
    |> case do
      {:ok, token, _claims} -> {:ok, token}
      _ -> :error
    end
  end
end
