defmodule NervesHubWeb do
  @moduledoc """
  The entrypoint for defining your web interface, such
  as controllers, views, channels and so on.

  This can be used in your application as:

      use NervesHubWeb, :controller
      use NervesHubWeb, :view

  The definitions below will be executed for every view,
  controller, etc, so keep them short and clean, focused
  on imports, uses and aliases.

  Do NOT define functions inside the quoted expressions
  below. Instead, define any helper function in modules
  and import those modules here.
  """

  def static_paths(), do: ~w(assets fonts images favicon.ico robots.txt)

  def plug() do
    quote do
      @behaviour Plug
      import Plug.Conn
      import Phoenix.Controller
    end
  end

  def controller() do
    quote do
      use Phoenix.Controller, namespace: NervesHubWeb
      use Gettext, backend: NervesHubWeb.Gettext

      import Plug.Conn
      import Phoenix.LiveView.Controller
      import NervesHub.RoleValidateHelpers

      import Phoenix.LiveView.Controller

      alias NervesHubWeb.Router.Helpers, as: Routes

      # Routes generation with the ~p sigil
      unquote(verified_routes())

      def whitelist(params, keys) do
        keys
        |> Enum.filter(fn x -> !is_nil(params[to_string(x)]) end)
        |> Enum.into(%{}, fn x -> {x, params[to_string(x)]} end)
      end
    end
  end

  def api_controller() do
    quote do
      use Phoenix.Controller, namespace: NervesHubWeb
      use Gettext, backend: NervesHubWeb.Gettext

      import Plug.Conn
      import Phoenix.LiveView.Controller
      import NervesHub.RoleValidateHelpers

      import Phoenix.LiveView.Controller

      alias NervesHubWeb.Router.Helpers, as: Routes

      def whitelist(params, keys) do
        keys
        |> Enum.filter(fn x -> !is_nil(params[to_string(x)]) end)
        |> Enum.into(%{}, fn x -> {x, params[to_string(x)]} end)
      end
    end
  end

  def updated_live_view() do
    quote do
      use NervesHubWeb.LiveView,
        layout: {NervesHubWeb.LayoutView, :live},
        container: {:div, class: "h-screen"}

      use Gettext, backend: NervesHubWeb.Gettext

      # HTML escaping functionality
      import Phoenix.HTML

      import NervesHubWeb.Helpers.Authorization

      # Shortcut for generating JS commands
      alias Phoenix.LiveView.JS

      alias NervesHubWeb.Components.Navigation

      # Routes generation with the ~p sigil
      unquote(verified_routes())

      unquote(view_helpers())

      on_mount(Sentry.LiveViewHook)

      def ok(socket), do: {:ok, socket}

      def noreply(socket), do: {:noreply, socket}

      def page_title(socket, page_title), do: assign(socket, :page_title, page_title)

      def sidebar_tab(socket, tab) do
        socket
        |> assign(:sidebar_tab, tab)
        |> assign(:tab_hint, tab)
      end

      def send_toast(socket, kind, msg) do
        NervesHubWeb.LiveToast.send_toast(kind, msg)
        socket
      end

      def whitelist(params, keys) do
        keys
        |> Enum.filter(fn x -> !is_nil(params[to_string(x)]) end)
        |> Enum.into(%{}, fn x -> {x, params[to_string(x)]} end)
      end
    end
  end

  def verified_routes() do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: NervesHubWeb.Endpoint,
        router: NervesHubWeb.Router,
        statics: NervesHubWeb.static_paths()
    end
  end

  def live_component() do
    quote do
      use Phoenix.LiveComponent

      import NervesHubWeb.Helpers.Authorization

      def ok(socket), do: {:ok, socket}

      def noreply(socket), do: {:noreply, socket}

      def page_title(socket, page_title), do: assign(socket, :page_title, page_title)

      def sidebar_tab(socket, tab) do
        socket
        |> assign(:sidebar_tab, tab)
        |> assign(:tab_hint, tab)
      end

      def send_toast(socket, kind, msg) do
        NervesHubWeb.LiveToast.send_toast(kind, msg)
        socket
      end

      # Routes generation with the ~p sigil
      unquote(verified_routes())

      unquote(view_helpers())
    end
  end

  def html() do
    quote do
      use Phoenix.Component

      # Import convenience functions from controllers
      import Phoenix.Controller,
        only: [get_csrf_token: 0, view_module: 1, view_template: 1]

      # Include general helpers for rendering HTML
      unquote(html_helpers())
    end
  end

  defp html_helpers() do
    quote do
      # HTML escaping functionality
      import Phoenix.HTML
      # Core UI components and translation
      import NervesHubWeb.CoreComponents
      import NervesHubWeb.Gettext

      # Shortcut for generating JS commands
      alias Phoenix.LiveView.JS

      # Routes generation with the ~p sigil
      unquote(verified_routes())
    end
  end

  def view() do
    quote do
      use Phoenix.View,
        root: "lib/nerves_hub_web/templates",
        namespace: NervesHubWeb

      alias NervesHubWeb.DeviceLive
      alias NervesHubWeb.Endpoint

      alias NervesHubWeb.Components.Navigation

      # Import convenience functions from controllers
      import Phoenix.Controller,
        only: [get_flash: 1, get_flash: 2, view_module: 1, view_template: 1]

      import Phoenix.Component

      import NervesHubWeb.Components.SimpleActiveLink

      # Include shared imports and aliases for views
      unquote(view_helpers())

      # Routes generation with the ~p sigil
      unquote(verified_routes())
    end
  end

  def api_view() do
    quote do
      use Phoenix.View,
        root: "lib/nerves_hub_web/templates",
        namespace: NervesHubWeb

      use Gettext, backend: NervesHubWeb.Gettext

      # Import convenience functions from controllers
      import Phoenix.Controller, only: [get_flash: 2, view_module: 1]

      import NervesHubWeb.ErrorHelpers

      alias NervesHubWeb.Router.Helpers, as: Routes

      def render("error.json", %{error: error}) do
        %{
          error: error
        }
      end
    end
  end

  def component() do
    quote do
      use Phoenix.Component

      # Routes generation with the ~p sigil
      unquote(verified_routes())
    end
  end

  def router() do
    quote do
      use Phoenix.Router
      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def channel() do
    quote do
      use Phoenix.Channel
      use Gettext, backend: NervesHubWeb.Gettext
    end
  end

  defp view_helpers() do
    quote do
      # Use all HTML functionality (forms, tags, etc)
      use Phoenix.HTML
      use Gettext, backend: NervesHubWeb.Gettext

      # Import LiveView helpers (live_render, live_component, live_patch, etc)
      import Phoenix.LiveView.Helpers

      # Import basic rendering functionality (render, render_layout, etc)
      import Phoenix.View

      import NervesHubWeb.ErrorHelpers
      alias NervesHubWeb.Router.Helpers, as: Routes
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
