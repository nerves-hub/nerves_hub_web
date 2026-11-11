defmodule NervesHubWeb.Access.AuthorizedLiveViewTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.Accounts
  alias NervesHub.Accounts.Scope
  alias NervesHubWeb.Access.Authorization
  alias NervesHubWeb.Access.AuthorizedTab
  alias NervesHubWeb.Mounts.RequireAuthorization
  alias NervesHubWeb.Mounts.RequireAuthorization.AuthorizationFailed
  alias NervesHubWeb.Mounts.RequireAuthorization.AuthorizationNotApplied
  alias Phoenix.LiveView.Socket

  # A LiveView whose mount says it authorizes in its body, and then does not
  defmodule UndecoratedMountLive do
    use Phoenix.LiveView
    use NervesHubWeb.Access.AuthorizedLiveView

    @decorate authorizes_in_body()
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

  # A LiveView where an event says it authorizes in its body, and then does not
  defmodule UndecoratedEventLive do
    use Phoenix.LiveView
    use NervesHubWeb.Access.AuthorizedLiveView

    @decorate requires_no_permission()
    def mount(_params, _session, socket) do
      {:ok, socket}
    end

    @decorate authorizes_in_body()
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

    import RequireAuthorization, only: [authorize!: 3]

    @decorate authorizes_in_body()
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

    import RequireAuthorization, only: [authorize!: 3]

    @decorate requires_no_permission()
    def mount(_params, _session, socket) do
      {:ok, socket}
    end

    @decorate authorizes_in_body()
    def handle_event("delete", _params, socket) do
      socket = authorize!(socket, :"device:delete", socket.assigns.device)
      {:noreply, socket}
    end

    def render(assigns), do: ~H"<div>test</div>"
  end

  # A LiveView that destructures the socket in the function head. The decorator
  # must not re-inject the pattern match into the body; if it did, `scope` would
  # be re-bound and shadow the head match (compiler warning + broken hygiene).
  defmodule HeadPatternMatchLive do
    use Phoenix.LiveView
    use NervesHubWeb.Access.AuthorizedLiveView

    @decorate requires_permission(:"device:list")
    def mount(_params, _session, %{assigns: %{current_scope: scope}} = socket) do
      {:ok, Phoenix.Component.assign(socket, :matched_product_id, scope.product.id)}
    end

    def render(assigns), do: ~H"<div>test</div>"
  end

  # A LiveView using special_permission — the body does its own check.
  defmodule SpecialPermissionLive do
    use Phoenix.LiveView
    use NervesHubWeb.Access.AuthorizedLiveView

    @decorate requires_no_permission()
    def mount(_params, _session, socket) do
      {:ok, socket}
    end

    @decorate special_permission(:checked_in_body)
    def handle_event("custom", _params, socket) do
      {:noreply, socket}
    end

    def render(assigns), do: ~H"<div>test</div>"
  end

  # A LiveView returning a {:reply, msg, socket} 3-tuple from a decorated event.
  defmodule ReplyTupleEventLive do
    use Phoenix.LiveView
    use NervesHubWeb.Access.AuthorizedLiveView

    @decorate requires_no_permission()
    def mount(_params, _session, socket) do
      {:ok, socket}
    end

    @decorate requires_no_permission()
    def handle_event("ping", _params, socket) do
      {:reply, %{pong: true}, socket}
    end

    def render(assigns), do: ~H"<div>test</div>"
  end

  # A LiveView returning {:ok, socket, opts} from a decorated mount.
  defmodule MountWithOptsLive do
    use Phoenix.LiveView
    use NervesHubWeb.Access.AuthorizedLiveView

    @decorate requires_no_permission()
    def mount(_params, _session, socket) do
      {:ok, socket, layout: false}
    end

    def render(assigns), do: ~H"<div>test</div>"
  end

  # A LiveView whose event fails for a reason that has nothing to do with
  # authorization.
  defmodule CrashingEventLive do
    use Phoenix.LiveView
    use NervesHubWeb.Access.AuthorizedLiveView

    @decorate requires_no_permission()
    def mount(_params, _session, socket) do
      {:ok, socket}
    end

    @decorate requires_no_permission()
    def handle_event("crash", %{"count" => count}, socket) do
      {:noreply, Phoenix.Component.assign(socket, :count, String.to_integer(count))}
    end

    def render(assigns), do: ~H"<div>test</div>"
  end

  # A LiveView with no handle_params/3 of its own.
  defmodule NoParamsLive do
    use Phoenix.LiveView
    use NervesHubWeb.Access.AuthorizedLiveView

    @decorate requires_no_permission()
    def mount(_params, _session, socket) do
      {:ok, socket}
    end

    def render(assigns), do: ~H"<div>test</div>"
  end

  # A LiveView whose handle_params/3 fails to match further down.
  defmodule BrokenParamsLive do
    use Phoenix.LiveView
    use NervesHubWeb.Access.AuthorizedLiveView

    @decorate requires_no_permission()
    def mount(_params, _session, socket) do
      {:ok, socket}
    end

    @decorate requires_no_permission()
    def handle_params(params, _uri, socket) do
      {:noreply, picky(params, socket)}
    end

    defp picky(%{"expected" => _}, socket), do: socket

    def render(assigns), do: ~H"<div>test</div>"
  end

  # A LiveView that uses the older authorized!/2 helper in the body.
  defmodule LegacyCheckLive do
    use Phoenix.LiveView
    use NervesHubWeb.Access.AuthorizedLiveView

    import NervesHubWeb.Helpers.Authorization, only: [authorized!: 2]

    @decorate requires_no_permission()
    def mount(_params, _session, socket) do
      {:ok, socket}
    end

    @decorate special_permission(:enforced_by_authorized_bang)
    def handle_event("delete", _params, socket) do
      authorized!(:"device:delete", socket.assigns.current_scope)
      {:noreply, Phoenix.Component.assign(socket, :deleted, true)}
    end

    def render(assigns), do: ~H"<div>test</div>"
  end

  # A LiveView that checks a permission against a record in the assigns.
  defmodule OnAssignLive do
    use Phoenix.LiveView
    use NervesHubWeb.Access.AuthorizedLiveView

    @decorate requires_no_permission()
    def mount(_params, _session, socket) do
      {:ok, socket}
    end

    @decorate requires_permission(:"device:delete", on: :device)
    def handle_event("delete", _params, socket) do
      {:noreply, Phoenix.Component.assign(socket, :deleted, true)}
    end

    def render(assigns), do: ~H"<div>test</div>"
  end

  # A LiveComponent, whose events never reach the LiveView.
  defmodule EventComponent do
    use Phoenix.LiveComponent
    use NervesHubWeb.Access.AuthorizedLiveComponent

    @decorate requires_permission(:"device:delete", on: :device)
    def handle_event("delete", _params, socket) do
      {:noreply, Phoenix.Component.assign(socket, :deleted, true)}
    end

    @decorate authorizes_in_body()
    def handle_event("forgot", _params, socket) do
      {:noreply, socket}
    end

    @decorate requires_no_permission()
    def handle_event("crash", %{"count" => count}, socket) do
      {:noreply, Phoenix.Component.assign(socket, :count, String.to_integer(count))}
    end

    def render(assigns), do: ~H"<div>test</div>"
  end

  # A device page tab, whose hook halts events before the LiveView sees them.
  defmodule EventTab do
    use Phoenix.Component
    use AuthorizedTab

    @decorate requires_permission(:"device:delete", on: :device)
    def hooked_event("delete", _params, socket) do
      {:halt, Phoenix.Component.assign(socket, :deleted, true)}
    end

    @decorate authorizes_in_body()
    def hooked_event("forgot", _params, socket) do
      {:halt, socket}
    end

    @decorate requires_no_permission()
    def hooked_event(_event, _params, socket), do: {:cont, socket}

    @decorate requires_permission(:"device:update", on: :device)
    def handle_progress(:file, _entry, socket) do
      {:noreply, Phoenix.Component.assign(socket, :uploaded, true)}
    end

    def progress(), do: authorized_progress(&handle_progress/3)
  end

  defp build_socket(extra_assigns \\ %{}) do
    assigns =
      %{__changed__: %{}}
      |> Map.merge(extra_assigns)

    %Socket{
      private: %{
        live_temp: %{},
        wrapped_in_authorization?: false,
        authorization_applied?: false,
        authorization_granted?: false
      },
      assigns: assigns
    }
  end

  defp build_scope(user, org, product) do
    org_user = Accounts.get_org_user!(org, user.id)

    Scope.for_user(user)
    |> Scope.put_org(org)
    |> Scope.put_role(org_user.role)
    |> Scope.put_product(product)
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

  describe "head pattern matching" do
    test "preserves head-matched variables through requires_permission", %{
      user: user,
      org: org,
      product: product
    } do
      scope = build_scope(user, org, product)
      socket = build_socket(%{current_scope: scope})

      assert {:ok, socket} = HeadPatternMatchLive.mount(%{}, %{}, socket)
      assert socket.assigns.matched_product_id == product.id
      assert socket.private.authorization_granted?
    end
  end

  describe "special_permission" do
    test "marks the socket as authorized via the supplied reason" do
      socket = build_socket()
      {:ok, socket} = DecoratedMountLive.mount(%{}, %{}, socket)
      socket = reset_authorization(socket)

      assert {:noreply, socket} = SpecialPermissionLive.handle_event("custom", %{}, socket)
      assert socket.private.authorization_granted?
      assert socket.private.authorization_info == :checked_in_body
    end
  end

  describe "return shapes" do
    test "preserves {:reply, msg, socket} from a decorated handle_event" do
      socket = build_socket()
      {:ok, socket} = DecoratedMountLive.mount(%{}, %{}, socket)
      socket = reset_authorization(socket)

      assert {:reply, %{pong: true}, socket} =
               ReplyTupleEventLive.handle_event("ping", %{}, socket)

      assert socket.private.authorization_granted?
    end

    test "preserves {:ok, socket, opts} from a decorated mount" do
      socket = build_socket()

      assert {:ok, socket, layout: false} = MountWithOptsLive.mount(%{}, %{}, socket)
      assert socket.private.authorization_granted?
    end
  end

  describe "state between callbacks" do
    test "what one callback was granted does not carry over to the next" do
      socket = build_socket()
      {:ok, socket} = DecoratedMountLive.mount(%{}, %{}, socket)

      # No reset in between: the socket is exactly as mount/3 returned it.
      assert socket.private.authorization_granted?

      assert_raise AuthorizationNotApplied, fn ->
        UndecoratedEventLive.handle_event("click", %{}, socket)
      end
    end

    test "a socket that was never set up is still checked" do
      socket = %Socket{assigns: %{__changed__: %{}}}

      assert_raise AuthorizationNotApplied, fn ->
        UndecoratedMountLive.mount(%{}, %{}, socket)
      end

      assert_raise AuthorizationNotApplied, fn ->
        UndecoratedEventLive.handle_event("click", %{}, socket)
      end
    end
  end

  describe "failures" do
    test "an exception that isn't about authorization is not swallowed" do
      socket = build_socket(%{flash: %{}})
      {:ok, socket} = DecoratedMountLive.mount(%{}, %{}, socket)

      assert_raise ArgumentError, fn ->
        CrashingEventLive.handle_event("crash", %{"count" => "not a number"}, socket)
      end
    end

    test "a refused event keeps the socket from before the event and tells the user", %{
      user: user,
      org: org,
      product: product,
      device: device
    } do
      org_user = Accounts.get_org_user!(org, user.id)
      {:ok, _org_user} = Accounts.change_org_user_role(org_user, :view)

      scope = build_scope(user, org, product)
      socket = build_socket(%{current_scope: scope, device: device, flash: %{}})

      assert {:noreply, socket} = ExplicitAuthorizeEventLive.handle_event("delete", %{}, socket)
      assert socket.assigns.flash["error"] =~ "denied access"
      refute socket.redirected
    end

    test "a refusal from authorized!/2 in the body is handled the same way", %{
      user: user,
      org: org,
      product: product
    } do
      org_user = Accounts.get_org_user!(org, user.id)
      {:ok, _org_user} = Accounts.change_org_user_role(org_user, :view)

      scope = build_scope(user, org, product)
      socket = build_socket(%{current_scope: scope, flash: %{}})

      assert {:noreply, socket} = LegacyCheckLive.handle_event("delete", %{}, socket)
      assert socket.assigns.flash["error"] =~ "denied access"
      refute Map.has_key?(socket.assigns, :deleted)
    end

    test "a refused mount redirects, as there is nothing to render", %{
      user: user,
      org: org,
      product: product
    } do
      org_user = Accounts.get_org_user!(org, user.id)
      {:ok, _org_user} = Accounts.change_org_user_role(org_user, :view)

      scope = build_scope(user, org, product)
      socket = build_socket(%{current_scope: scope, flash: %{}})

      assert {:ok, socket} = ManagePermissionMountLive.mount(%{}, %{}, socket)
      assert socket.redirected == {:redirect, %{to: "/", status: 302}}
      assert socket.assigns.flash["error"] =~ "denied access"
    end
  end

  describe "a real page" do
    import Phoenix.LiveViewTest

    test "sends a member away when they lack the role to open it", %{conn: conn, user: user, org: org} do
      org_user = Accounts.get_org_user!(org, user.id)
      {:ok, _org_user} = Accounts.change_org_user_role(org_user, :view)

      assert {:error, {:redirect, %{to: "/", flash: flash}}} = live(conn, "/org/#{org.name}/settings/delete")
      assert flash["error"] =~ "denied access"
    end

    test "opens for a member who has the role", %{conn: conn, org: org} do
      assert {:ok, _view, _html} = live(conn, "/org/#{org.name}/settings/delete")
    end
  end

  describe "handle_params" do
    test "a LiveView without handle_params/3 passes" do
      socket = build_socket()
      {:ok, socket} = NoParamsLive.mount(%{}, %{}, socket)

      assert {:noreply, _socket} = NoParamsLive.handle_params(%{}, "http://localhost/", socket)
    end

    test "a clause error from deeper in handle_params/3 is not mistaken for a missing callback" do
      socket = build_socket()
      {:ok, socket} = BrokenParamsLive.mount(%{}, %{}, socket)

      assert_raise FunctionClauseError, fn ->
        BrokenParamsLive.handle_params(%{}, "http://localhost/", socket)
      end
    end
  end

  describe "a callback that does not state its authorization" do
    test "does not compile in a LiveView" do
      assert_raise CompileError, ~r/handle_event\/3 in .* does not state its authorization/, fn ->
        Code.compile_string("""
        defmodule NervesHubWeb.Access.AuthorizedLiveViewTest.SilentLive do
          use Phoenix.LiveView
          use NervesHubWeb.Access.AuthorizedLiveView

          @decorate requires_no_permission()
          def mount(_params, _session, socket), do: {:ok, socket}

          @decorate requires_no_permission()
          def handle_event("open", _params, socket), do: {:noreply, socket}

          def handle_event("delete", _params, socket), do: {:noreply, socket}

          def render(assigns), do: ~H"<div>test</div>"
        end
        """)
      end
    end

    test "does not compile in a LiveComponent" do
      assert_raise CompileError, ~r/handle_event\/3 in .* does not state its authorization/, fn ->
        Code.compile_string("""
        defmodule NervesHubWeb.Access.AuthorizedLiveViewTest.SilentComponent do
          use Phoenix.LiveComponent
          use NervesHubWeb.Access.AuthorizedLiveComponent

          def handle_event("delete", _params, socket), do: {:noreply, socket}

          def render(assigns), do: ~H"<div>test</div>"
        end
        """)
      end
    end

    test "does not compile in a tab, the clause that passes events on included" do
      assert_raise CompileError, ~r/hooked_event\/3 in .* does not state its authorization/, fn ->
        Code.compile_string("""
        defmodule NervesHubWeb.Access.AuthorizedLiveViewTest.SilentTab do
          use Phoenix.Component
          use NervesHubWeb.Access.AuthorizedTab

          def hooked_event(_event, _params, socket), do: {:cont, socket}
        end
        """)
      end
    end

    test "does not compile for an upload's progress function" do
      assert_raise CompileError, ~r/handle_progress\/3 in .* does not state its authorization/, fn ->
        Code.compile_string("""
        defmodule NervesHubWeb.Access.AuthorizedLiveViewTest.SilentUpload do
          use Phoenix.Component
          use NervesHubWeb.Access.AuthorizedTab

          def handle_progress(:file, _entry, socket), do: {:noreply, socket}
        end
        """)
      end
    end
  end

  describe "a permission on a record in the assigns" do
    setup %{user: user, org: org, product: product, device: device} do
      other_org = NervesHub.Fixtures.org_fixture(NervesHub.Fixtures.user_fixture(), %{name: "elsewhere"})

      %{manager: %{build_scope(user, org, product) | role: :manage}, device: device, other_org: other_org}
    end

    test "is granted for a record in the user's org", %{manager: manager, device: device} do
      socket = build_socket(%{current_scope: manager, device: device, flash: %{}})

      assert {:noreply, socket} = OnAssignLive.handle_event("delete", %{}, socket)
      assert socket.assigns.deleted
    end

    test "is refused for a record in another org, whatever the role", %{
      manager: manager,
      device: device,
      other_org: other_org
    } do
      socket = build_socket(%{current_scope: manager, device: %{device | org_id: other_org.id}, flash: %{}})

      assert {:noreply, socket} = OnAssignLive.handle_event("delete", %{}, socket)
      refute Map.has_key?(socket.assigns, :deleted)
      assert socket.assigns.flash["error"] =~ "denied access"
    end
  end

  describe "a LiveComponent's events" do
    setup %{user: user, org: org, product: product, device: device} do
      scope = build_scope(user, org, product)

      %{viewer: %{scope | role: :view}, manager: %{scope | role: :manage}, device: device}
    end

    test "run when the user has the permission", %{manager: manager, device: device} do
      socket = build_socket(%{current_scope: manager, device: device, flash: %{}, myself: 1})

      assert {:noreply, socket} = EventComponent.handle_event("delete", %{}, socket)
      assert socket.assigns.deleted
      refute_received _
    end

    test "are refused without it, and the LiveView is asked to tell the user", %{viewer: viewer, device: device} do
      socket = build_socket(%{current_scope: viewer, device: device, flash: %{}, myself: 1})

      assert {:noreply, refused} = EventComponent.handle_event("delete", %{}, socket)
      refute Map.has_key?(refused.assigns, :deleted)
      assert_received {RequireAuthorization, :denied_in_component}
    end

    test "raise when the body was meant to authorize and did not", %{manager: manager, device: device} do
      socket = build_socket(%{current_scope: manager, device: device, flash: %{}, myself: 1})

      assert_raise AuthorizationNotApplied, fn -> EventComponent.handle_event("forgot", %{}, socket) end
    end

    test "let other exceptions through" do
      assert_raise ArgumentError, fn ->
        EventComponent.handle_event("crash", %{"count" => "many"}, build_socket(%{flash: %{}}))
      end
    end
  end

  describe "a tab's events" do
    setup %{user: user, org: org, product: product, device: device} do
      scope = build_scope(user, org, product)

      %{viewer: %{scope | role: :view}, manager: %{scope | role: :manage}, device: device}
    end

    test "run when the user has the permission", %{manager: manager, device: device} do
      socket = build_socket(%{current_scope: manager, device: device, flash: %{}})

      assert {:halt, socket} = EventTab.authorized_hooked_event("delete", %{}, socket)
      assert socket.assigns.deleted
    end

    test "are refused without it: the event stops there and the user is told", %{viewer: viewer, device: device} do
      socket = build_socket(%{current_scope: viewer, device: device, flash: %{}})

      assert {:halt, refused} = EventTab.authorized_hooked_event("delete", %{}, socket)
      refute Map.has_key?(refused.assigns, :deleted)
      assert refused.assigns.flash["error"] =~ "denied access"
    end

    test "raise when the body was meant to authorize and did not", %{manager: manager, device: device} do
      socket = build_socket(%{current_scope: manager, device: device, flash: %{}})

      assert_raise AuthorizationNotApplied, fn -> AuthorizedTab.run(EventTab, "forgot", %{}, socket) end
    end

    test "an event the tab passes on reaches the LiveView unchecked, for it to check", %{
      manager: manager,
      device: device
    } do
      socket = build_socket(%{current_scope: manager, device: device, flash: %{}})

      assert {:cont, socket} = EventTab.authorized_hooked_event("something-else", %{}, socket)
      refute socket.private.wrapped_in_authorization?

      assert_raise AuthorizationNotApplied, fn -> UndecoratedEventLive.handle_event("click", %{}, socket) end
    end

    test "an upload's progress is checked, and a refusal is not softened", %{
      viewer: viewer,
      manager: manager,
      device: device
    } do
      socket = build_socket(%{current_scope: manager, device: device, flash: %{}})
      assert {:noreply, socket} = EventTab.progress().(:file, %{}, socket)
      assert socket.assigns.uploaded

      socket = build_socket(%{current_scope: viewer, device: device, flash: %{}})
      assert_raise AuthorizationFailed, fn -> EventTab.progress().(:file, %{}, socket) end
    end
  end

  describe "the ways around the check" do
    @web_sources Path.wildcard("lib/nerves_hub_web/**/*.{ex,heex}") -- ["lib/nerves_hub_web.ex"]

    test "no LiveView or LiveComponent is defined without going through NervesHubWeb" do
      assert offenders(~r/use Phoenix\.Live(View|Component)\b/) == []
    end

    test "no event hook is attached other than the checked one the tabs use" do
      assert offenders(~r/attach_hook\([^\n]*:handle_event/) == []

      assert File.read!("lib/nerves_hub_web.ex") =~
               "attach_hook(tab_hook_id(), :handle_event, &__MODULE__.authorized_hooked_event/3)"
    end

    test "every upload's progress function is a checked one" do
      assert offenders(~r/\bprogress: (?!authorized_progress\(&handle_progress\/3\))[&f]/) == []
    end

    defp offenders(pattern) do
      for file <- @web_sources,
          {line, number} <- file |> File.read!() |> String.split("\n") |> Enum.with_index(1),
          line =~ pattern,
          do: "#{file}:#{number}"
    end
  end

  describe "the two permission tables" do
    # Templates decide what to show from NervesHubWeb.Helpers.Authorization, the
    # callbacks decide what to allow from NervesHubWeb.Access.Authorization. A
    # permission both know about must need the same role in both.
    test "agree on the role each shared permission needs", %{user: user, org: org, product: product, device: device} do
      shared = shared_permissions()
      assert length(shared) > 30

      for role <- [:view, :manage, :admin] do
        scope = %{build_scope(user, org, product) | role: role}

        for permission <- shared, subject <- [org, product, device], applies?(permission, scope, subject) do
          assert Authorization.authorized?(permission, scope, subject) ==
                   NervesHubWeb.Helpers.Authorization.authorized?(permission, scope),
                 "#{permission} disagrees for the #{role} role"
        end
      end
    end
  end

  defp shared_permissions() do
    permissions = fn module, arity ->
      {:ok, {_, [abstract_code: {_, forms}]}} = :beam_lib.chunks(:code.which(module), [:abstract_code])

      for {:function, _, :authorized?, ^arity, clauses} <- forms,
          {:clause, _, [{:atom, _, permission} | _], _, _} <- clauses,
          uniq: true,
          do: permission
    end

    old = permissions.(NervesHubWeb.Helpers.Authorization, 2)
    new = permissions.(Authorization, 3)

    Enum.filter(old, &(&1 in new))
  end

  defp applies?(permission, scope, subject) do
    Authorization.authorized?(permission, scope, subject)
    true
  rescue
    FunctionClauseError -> false
  end
end
