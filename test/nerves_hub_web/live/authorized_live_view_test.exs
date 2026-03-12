defmodule NervesHubWeb.Access.AuthorizedLiveViewTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.Accounts
  alias NervesHub.Accounts.Scope
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

  # A LiveView that uses explicit authorize! for entity-specific permission
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

  # A LiveView that uses explicit authorize! in handle_event
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

  defp build_scope(user, org, product \\ nil) do
    org_user = Accounts.get_org_user!(org, user.id)

    scope =
      Scope.for_user(user)
      |> Scope.put_org(org)
      |> Scope.put_role(org_user.role)

    if product do
      Scope.put_product(scope, product)
    else
      scope
    end
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

    test "passes when mount uses requires_permission with sufficient role", %{
      user: user,
      org: org,
      product: product
    } do
      scope = build_scope(user, org, product)
      socket = build_socket(%{current_scope: scope})

      assert {:ok, _socket} = PermissionMountLive.mount(%{}, %{}, socket)
    end

    test "catches authorization failure when role is insufficient", %{
      user: user,
      org: org,
      product: product
    } do
      org_user = Accounts.get_org_user!(org, user.id)
      {:ok, _org_user} = Accounts.change_org_user_role(org_user, :view)

      scope = build_scope(user, org, product)
      socket = build_socket(%{current_scope: scope})

      # device:create requires :manage, but user has :view role
      assert_raise AuthorizationFailed, fn ->
        ManagePermissionMountLive.mount(%{}, %{}, socket)
      end
    end
  end

  describe "explicit authorize! with entity-specific permissions" do
    test "passes when using authorize! with entity and sufficient role", %{
      user: user,
      org: org,
      product: product,
      device: device
    } do
      scope = build_scope(user, org, product)
      socket = build_socket(%{current_scope: scope, device: device})

      assert {:ok, _socket} = ExplicitAuthorizeMountLive.mount(%{}, %{}, socket)
    end

    test "raises AuthorizationFailed when role is insufficient for entity permission", %{
      user: user,
      org: org,
      product: product,
      device: device
    } do
      org_user = Accounts.get_org_user!(org, user.id)
      {:ok, _org_user} = Accounts.change_org_user_role(org_user, :view)

      scope = build_scope(user, org, product)
      socket = build_socket(%{current_scope: scope, device: device})

      # device:delete requires :manage, but user has :view role
      assert_raise AuthorizationFailed, fn ->
        ExplicitAuthorizeEventLive.handle_event("delete", %{}, socket)
      end
    end

    test "passes authorize! in handle_event with sufficient role", %{
      user: user,
      org: org,
      product: product,
      device: device
    } do
      scope = build_scope(user, org, product)
      socket = build_socket(%{current_scope: scope, device: device})
      {:ok, socket} = DecoratedMountLive.mount(%{}, %{}, socket)
      socket = reset_authorization(socket)

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
