defmodule NervesHubWeb.Access.AuthorizedLiveViewTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.Accounts
  alias NervesHubWeb.Mounts.RequireAuthorization.AuthorizationFailed
  alias NervesHubWeb.Mounts.RequireAuthorization.AuthorizationNotApplied
  alias Phoenix.LiveView.Socket

  # A LiveView with NO authorization decorator on mount
  defmodule UndecoratedMountLive do
    use Phoenix.LiveView
    use NervesHubWeb.Access.AuthorizedLiveView

    def mount(_params, _session, socket) do
      {:ok, socket}
    end

    def render(assigns), do: ~H"<div>test</div>"
  end

  # A LiveView with requires_no_permission on mount
  defmodule DecoratedMountLive do
    use Phoenix.LiveView
    use NervesHubWeb.Access.AuthorizedLiveView

    @decorate requires_no_permission()
    def mount(_params, _session, socket) do
      {:ok, socket}
    end

    def render(assigns), do: ~H"<div>test</div>"
  end

  # A LiveView with requires_permission on mount (device:list allows :view role, takes Product)
  defmodule PermissionMountLive do
    use Phoenix.LiveView
    use NervesHubWeb.Access.AuthorizedLiveView

    @decorate requires_permission(:"device:list")
    def mount(_params, _session, socket) do
      {:ok, socket}
    end

    def render(assigns), do: ~H"<div>test</div>"
  end

  # A LiveView with requires_permission that needs :manage role (device:create)
  defmodule ManagePermissionMountLive do
    use Phoenix.LiveView
    use NervesHubWeb.Access.AuthorizedLiveView

    @decorate requires_permission(:"device:create")
    def mount(_params, _session, socket) do
      {:ok, socket}
    end

    def render(assigns), do: ~H"<div>test</div>"
  end

  # A LiveView where mount is decorated but an event is NOT
  defmodule UndecoratedEventLive do
    use Phoenix.LiveView
    use NervesHubWeb.Access.AuthorizedLiveView

    @decorate requires_no_permission()
    def mount(_params, _session, socket) do
      {:ok, socket}
    end

    def handle_event("click", _params, socket) do
      {:noreply, socket}
    end

    def render(assigns), do: ~H"<div>test</div>"
  end

  # A LiveView where both mount and event are decorated
  defmodule DecoratedEventLive do
    use Phoenix.LiveView
    use NervesHubWeb.Access.AuthorizedLiveView

    @decorate requires_no_permission()
    def mount(_params, _session, socket) do
      {:ok, socket}
    end

    @decorate requires_no_permission()
    def handle_event("click", _params, socket) do
      {:noreply, socket}
    end

    def render(assigns), do: ~H"<div>test</div>"
  end

  # A LiveView that uses explicit authorize! instead of decorators for entity-specific permission
  defmodule ExplicitAuthorizeMountLive do
    use Phoenix.LiveView
    use NervesHubWeb.Access.AuthorizedLiveView

    import NervesHubWeb.Mounts.RequireAuthorization, only: [authorize!: 3]

    def mount(_params, _session, socket) do
      socket = authorize!(socket, :"device:view", socket.assigns.device)
      {:ok, socket}
    end

    def render(assigns), do: ~H"<div>test</div>"
  end

  # A LiveView that uses explicit authorize! in handle_event for entity-specific permission
  defmodule ExplicitAuthorizeEventLive do
    use Phoenix.LiveView
    use NervesHubWeb.Access.AuthorizedLiveView

    import NervesHubWeb.Mounts.RequireAuthorization, only: [authorize!: 3]

    @decorate requires_no_permission()
    def mount(_params, _session, socket) do
      {:ok, socket}
    end

    def handle_event("delete", _params, socket) do
      socket = authorize!(socket, :"device:delete", socket.assigns.device)
      {:noreply, socket}
    end

    def render(assigns), do: ~H"<div>test</div>"
  end

  defp build_socket(extra_assigns \\ %{}) do
    assigns =
      %{__changed__: %{}}
      |> Map.merge(extra_assigns)

    %Socket{
      private: %{
        wrapped_in_authorization?: false,
        authorization_applied?: false,
        authorization_granted?: false
      },
      assigns: assigns
    }
  end

  defp reset_authorization(socket) do
    %{
      socket
      | private:
          Map.merge(socket.private, %{
            wrapped_in_authorization?: false,
            authorization_applied?: false,
            authorization_granted?: false
          })
    }
  end

  describe "mount authorization enforcement" do
    test "catches missing authorization on mount" do
      socket = build_socket()

      assert_raise AuthorizationNotApplied, fn ->
        UndecoratedMountLive.mount(%{}, %{}, socket)
      end
    end

    test "passes when mount uses requires_no_permission" do
      socket = build_socket()

      assert {:ok, _socket} = DecoratedMountLive.mount(%{}, %{}, socket)
    end

    test "passes when mount uses requires_permission with sufficient role", %{user: user, org: org, product: product} do
      org_user = Accounts.get_org_user!(org, user)
      socket = build_socket(%{org_user: org_user, product: product})

      assert {:ok, _socket} = PermissionMountLive.mount(%{}, %{}, socket)
    end

    test "catches authorization failure when role is insufficient", %{user: user, org: org, product: product} do
      org_user = Accounts.get_org_user!(org, user)
      {:ok, _org_user} = Accounts.change_org_user_role(org_user, :view)
      org_user = Accounts.get_org_user!(org, user)
      socket = build_socket(%{org_user: org_user, product: product})

      # device:create requires :manage, but user has :view role
      assert_raise AuthorizationFailed, fn ->
        ManagePermissionMountLive.mount(%{}, %{}, socket)
      end
    end
  end

  describe "explicit authorize! with entity-specific permissions" do
    test "passes when using authorize! with entity and sufficient role", %{user: user, org: org, device: device} do
      org_user = Accounts.get_org_user!(org, user)
      socket = build_socket(%{org_user: org_user, device: device})

      assert {:ok, _socket} = ExplicitAuthorizeMountLive.mount(%{}, %{}, socket)
    end

    test "raises AuthorizationFailed when role is insufficient for entity permission", %{
      user: user,
      org: org,
      device: device
    } do
      org_user = Accounts.get_org_user!(org, user)
      {:ok, _org_user} = Accounts.change_org_user_role(org_user, :view)
      org_user = Accounts.get_org_user!(org, user)
      socket = build_socket(%{org_user: org_user, device: device})

      # device:delete requires :manage, but user has :view role
      assert_raise AuthorizationFailed, fn ->
        ExplicitAuthorizeEventLive.handle_event("delete", %{}, socket)
      end
    end

    test "passes authorize! in handle_event with sufficient role", %{user: user, org: org, device: device} do
      org_user = Accounts.get_org_user!(org, user)
      socket = build_socket(%{org_user: org_user, device: device})
      {:ok, socket} = DecoratedMountLive.mount(%{}, %{}, socket)
      socket = reset_authorization(socket)
      socket = %{socket | assigns: Map.put(socket.assigns, :device, device)}

      assert {:noreply, _socket} = ExplicitAuthorizeEventLive.handle_event("delete", %{}, socket)
    end
  end

  describe "event authorization enforcement" do
    test "catches missing authorization on handle_event" do
      socket = build_socket()
      {:ok, socket} = DecoratedMountLive.mount(%{}, %{}, socket)
      socket = reset_authorization(socket)

      assert_raise AuthorizationNotApplied, fn ->
        UndecoratedEventLive.handle_event("click", %{}, socket)
      end
    end

    test "passes when handle_event uses requires_no_permission" do
      socket = build_socket()
      {:ok, socket} = DecoratedMountLive.mount(%{}, %{}, socket)
      socket = reset_authorization(socket)

      assert {:noreply, _socket} = DecoratedEventLive.handle_event("click", %{}, socket)
    end
  end
end
