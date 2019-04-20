defmodule NervesHubWWWWeb do
  @moduledoc """
  The entrypoint for defining your web interface, such
  as controllers, views, channels and so on.

  This can be used in your application as:

      use NervesHubWWWWeb, :controller
      use NervesHubWWWWeb, :view

  The definitions below will be executed for every view,
  controller, etc, so keep them short and clean, focused
  on imports, uses and aliases.

  Do NOT define functions inside the quoted expressions
  below. Instead, define any helper function in modules
  and import those modules here.
  """

  def controller do
    quote do
      use Phoenix.Controller, namespace: NervesHubWWWWeb
      import NervesHubWebCore.AuditLogs, only: [audit: 4, audit!: 4]
      import Plug.Conn
      import NervesHubWWWWeb.Router.Helpers
      import NervesHubWWWWeb.Gettext
      import Phoenix.LiveView.Controller, only: [live_render: 3]
      import NervesHubWebCore.RoleValidateHelpers

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

      alias NervesHubWebCore.{Repo, AuditLogs}
      alias NervesHubWWWWeb.Router.Helpers, as: Routes
      alias NervesHubWWWWeb.Endpoint

      alias Phoenix.Socket.Broadcast
    end
  end

  def view do
    quote do
      use Phoenix.View,
        root: "lib/nerves_hub_www_web/templates",
        namespace: NervesHubWWWWeb

      # Import convenience functions from controllers
      import Phoenix.Controller, only: [get_flash: 2, view_module: 1]
      import Phoenix.LiveView, only: [live_render: 2, live_render: 3]

      # Use all HTML functionality (forms, tags, etc)
      use Phoenix.HTML

      import NervesHubWWWWeb.Router.Helpers
      import NervesHubWWWWeb.ErrorHelpers
      import NervesHubWWWWeb.Gettext

      alias NervesHubWWWWeb.Router.Helpers, as: Routes
      alias NervesHubWWWWeb.Endpoint
    end
  end

  def api_view do
    quote do
      use Phoenix.View,
        root: "lib/nerves_hub_www_web/templates",
        namespace: NervesHubWWWWeb

      # Import convenience functions from controllers
      import Phoenix.Controller, only: [get_flash: 2, view_module: 1]

      import NervesHubWWWWeb.Router.Helpers
      import NervesHubWWWWeb.ErrorHelpers
      import NervesHubWWWWeb.Gettext

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
      import NervesHubWWWWeb.Gettext
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
