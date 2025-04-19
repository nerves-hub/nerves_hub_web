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
      use Phoenix.Controller, formats: [:html]

      use Gettext, backend: NervesHubWeb.Gettext

      import Plug.Conn

      import NervesHubWeb.Helpers.RoleValidateHelpers

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
      use Phoenix.Controller, formats: [:json]

      use Gettext, backend: NervesHubWeb.Gettext

      import Plug.Conn
      import Phoenix.LiveView.Controller
      import NervesHubWeb.Helpers.RoleValidateHelpers

      import Phoenix.LiveView.Controller

      alias NervesHubWeb.Router.Helpers, as: Routes

      action_fallback(NervesHubWeb.API.FallbackController)

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

      import NervesHubWeb.Components.Icons
      import NervesHubWeb.CoreComponents, only: [button: 1, input: 1, core_label: 1, error: 1]

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

      @spec sidebar_tab(
              Phoenix.Socket.t(),
              :archives | :firmware | :deployments | :devices | :settings | :support_scripts
            ) :: Phoenix.Socket.t()
      def sidebar_tab(socket, tab) do
        socket
        |> assign(:sidebar_tab, tab)
        |> assign(:tab_hint, tab)
      end

      def whitelist(params, keys) do
        keys
        |> Enum.filter(fn x -> !is_nil(params[to_string(x)]) end)
        |> Enum.into(%{}, fn x -> {x, params[to_string(x)]} end)
      end

      defp setup_tab_components(socket, tabs \\ []) do
        if socket.assigns[:new_ui] do
          Enum.reduce(tabs, socket, fn component, socket ->
            component.connect(socket)
          end)
          |> put_private(:tabs, tabs)
        else
          socket
        end
      end

      defp update_tab_component_hooks(socket) do
        if socket.assigns[:new_ui] do
          socket
          |> detach_hooks()
          |> attach_hooks()
        else
          socket
        end
      end

      defp detach_hooks(socket) do
        socket.private[:tabs]
        |> Enum.reduce(socket, fn component, socket ->
          component.detach_hooks(socket)
        end)
      end

      defp attach_hooks(socket) do
        socket.private[:tabs]
        |> Enum.reduce(socket, fn component, socket ->
          component.attach_hooks(socket)
        end)
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

      import NervesHubWeb.Components.Icons
      import NervesHubWeb.CoreComponents, only: [button: 1, input: 1, core_label: 1, error: 1]

      def ok(socket), do: {:ok, socket}

      def noreply(socket), do: {:noreply, socket}

      def page_title(socket, page_title), do: assign(socket, :page_title, page_title)

      def sidebar_tab(socket, tab) do
        socket
        |> assign(:sidebar_tab, tab)
        |> assign(:tab_hint, tab)
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

      alias NervesHubWeb.Layouts

      def platform_name(), do: Application.get_env(:nerves_hub, :support_email_platform_name)

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

  def component() do
    quote do
      use Phoenix.Component

      import NervesHubWeb.Components.Icons
      import NervesHubWeb.CoreComponents, only: [button: 1, input: 1, core_label: 1, error: 1]

      # Routes generation with the ~p sigil
      unquote(verified_routes())
    end
  end

  def hooked_component({:tab_id, tab_id}) do
    quote do
      use Phoenix.Component

      import NervesHubWeb.Components.Icons
      import NervesHubWeb.CoreComponents, only: [button: 1, input: 1, core_label: 1, error: 1]

      import NervesHubWeb.Helpers.Authorization

      import Phoenix.LiveView,
        only: [
          assign_async: 3,
          assign_async: 4,
          allow_upload: 3,
          attach_hook: 4,
          detach_hook: 3,
          push_patch: 2,
          push_event: 3,
          push_navigate: 2,
          start_async: 3,
          connected?: 1,
          consume_uploaded_entry: 3,
          put_flash: 3
        ]

      alias Phoenix.Socket.Broadcast

      @tab_id unquote(tab_id)

      defp tab_hook_id(), do: "#{@tab_id}_tab"

      def connect(socket) do
        attach_hook(socket, tab_hook_id(), :handle_params, &__MODULE__.hooked_params/3)
      end

      def attach_hooks(%{assigns: %{tab: tab}} = socket) when tab == @tab_id do
        socket
        |> attach_hook(tab_hook_id(), :handle_async, &__MODULE__.hooked_async/3)
        |> attach_hook(tab_hook_id(), :handle_event, &__MODULE__.hooked_event/3)
        |> attach_hook(tab_hook_id(), :handle_info, &__MODULE__.hooked_info/2)
      end

      def attach_hooks(socket), do: socket

      def detach_hooks(%{assigns: %{tab: tab}} = socket) do
        socket
        |> detach_hook(tab_hook_id(), :handle_async)
        |> detach_hook(tab_hook_id(), :handle_event)
        |> detach_hook(tab_hook_id(), :handle_info)
      end

      def hooked_params(params, uri, socket) do
        socket = assign(socket, :tab, socket.assigns.live_action)

        if socket.assigns.tab == @tab_id do
          tab_params(params, uri, socket)
        else
          cleanup()
          |> Enum.reduce(socket, fn key, acc ->
            new_assigns = Map.delete(acc.assigns, key)
            Map.put(acc, :assigns, new_assigns)
          end)
          |> cont()
        end
      end

      def tab_params(_params, _uri, socket) do
        cont(socket)
      end

      def cleanup() do
        []
      end

      defoverridable tab_params: 3, cleanup: 0

      def halt(socket), do: {:halt, socket}

      def cont(socket), do: {:cont, socket}

      def page_title(socket, page_title), do: assign(socket, :page_title, page_title)

      def sidebar_tab(socket, tab) do
        socket
        |> assign(:sidebar_tab, tab)
        |> assign(:tab_hint, tab)
      end

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

  defmacro __using__(tab_component: tab_id) do
    apply(__MODULE__, :hooked_component, tab_id: tab_id)
  end
end
