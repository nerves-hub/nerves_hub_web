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

  def plug do
    quote do
      import Plug.Conn
      import Phoenix.Controller
    end
  end

  def controller do
    quote do
      use Phoenix.Controller, namespace: NervesHubWeb

      import Plug.Conn
      import NervesHubWeb.Gettext
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

  def api_controller do
    quote do
      use Phoenix.Controller, namespace: NervesHubWeb

      import Plug.Conn
      import NervesHubWeb.Gettext
      import Phoenix.LiveView.Controller
      import NervesHub.RoleValidateHelpers

      import Phoenix.LiveView.Controller

      alias NervesHubWeb.APIRouter.Helpers, as: Routes

      def whitelist(params, keys) do
        keys
        |> Enum.filter(fn x -> !is_nil(params[to_string(x)]) end)
        |> Enum.into(%{}, fn x -> {x, params[to_string(x)]} end)
      end
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView

      alias NervesHub.{Repo, AuditLogs}

      alias NervesHubWeb.{
        DeviceLive,
        Endpoint
      }

      alias NervesHubWeb.Router.Helpers, as: Routes

      alias Phoenix.Socket.Broadcast

      defp socket_error(socket, error, opts \\ []) do
        redirect = opts[:redirect_to] || Routes.home_path(socket, :index)

        socket =
          socket
          |> put_flash(:info, error)
          |> redirect(to: redirect)

        {:ok, socket}
      end

      defp live_view_error(:update) do
        "The software running on NervesHub was updated to the latest version."
      end

      defp live_view_error(_) do
        "An error occurred while loading the view."
      end

      unquote(view_helpers())
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(view_helpers())
    end
  end

  def view do
    quote do
      use Phoenix.View,
        root: "lib/nerves_hub_web/templates",
        namespace: NervesHubWeb

      import PhoenixActiveLink

      alias NervesHubWeb.{DeviceLive, Endpoint}

      # Import convenience functions from controllers
      import Phoenix.Controller,
        only: [get_flash: 1, get_flash: 2, view_module: 1, view_template: 1]

      import Phoenix.LiveView.Helpers

      # Include shared imports and aliases for views
      unquote(view_helpers())
    end
  end

  def api_view do
    quote do
      use Phoenix.View,
        root: "lib/nerves_hub_web/templates",
        namespace: NervesHubWeb

      # Import convenience functions from controllers
      import Phoenix.Controller, only: [get_flash: 2, view_module: 1]

      import NervesHubWeb.ErrorHelpers
      import NervesHubWeb.Gettext

      alias NervesHubWeb.APIRouter.Helpers, as: Routes

      def render("error.json", %{error: error}) do
        %{
          error: error
        }
      end
    end
  end

  def router do
    quote do
      use Phoenix.Router
      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
      import NervesHubWeb.Gettext
    end
  end

  defp view_helpers do
    quote do
      # Use all HTML functionality (forms, tags, etc)
      use Phoenix.HTML

      # Import LiveView helpers (live_render, live_component, live_patch, etc)
      import Phoenix.LiveView.Helpers

      # Import basic rendering functionality (render, render_layout, etc)
      import Phoenix.View

      import NervesHubWeb.ErrorHelpers
      import NervesHubWeb.Gettext
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
