defmodule NervesHubWeb.AuthorizationDeclaredTest do
  use ExUnit.Case, async: true

  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.Scope
  alias NervesHub.Accounts.User

  defp compile(body) do
    name = Module.concat(__MODULE__, "M#{System.unique_integer([:positive])}")

    [{module, _}] =
      Code.compile_quoted(
        quote do
          defmodule unquote(name) do
            unquote(body)
          end
        end
      )

    module
  end

  defp socket(role) do
    scope =
      %User{id: 1}
      |> Scope.for_user()
      |> Scope.put_org(%Org{id: 1, name: "org"})
      |> then(&if(role, do: Scope.put_role(&1, role), else: &1))

    %{assigns: %{current_scope: scope}}
  end

  describe "callbacks a client can drive" do
    test "a clause without a decorator does not compile" do
      assert_raise CompileError, ~r/handle_event\/3 .* does not say what authorization it needs.*"undeclared"/s, fn ->
        compile(
          quote do
            use NervesHubWeb.AuthorizationDeclared, handle_event: 3

            @decorate requires_membership()
            def handle_event("declared", _params, socket), do: {:noreply, socket}

            def handle_event("undeclared", _params, socket), do: {:noreply, socket}
          end
        )
      end
    end

    test "callbacks that aren't listed need nothing" do
      module =
        compile(
          quote do
            use NervesHubWeb.AuthorizationDeclared, handle_event: 3

            def handle_info(_message, socket), do: {:noreply, socket}
          end
        )

      assert module.handle_info(:hello, :socket) == {:noreply, :socket}
    end

    test "requires_permission/1 refuses before the body runs" do
      module =
        compile(
          quote do
            use NervesHubWeb.AuthorizationDeclared, handle_event: 3

            @decorate requires_permission(:"device:reboot")
            def handle_event("reboot", _params, socket) do
              send(self(), :body_ran)
              {:noreply, socket}
            end
          end
        )

      assert_raise NervesHubWeb.UnauthorizedError, fn -> module.handle_event("reboot", %{}, socket(:view)) end
      refute_received :body_ran

      assert {:noreply, _} = module.handle_event("reboot", %{}, socket(:manage))
      assert_received :body_ran
    end

    test "requires_permission/1 reads the scope from a socket bound in a pattern" do
      module =
        compile(
          quote do
            use NervesHubWeb.AuthorizationDeclared, handle_event: 3

            @decorate requires_permission(:"device:reboot")
            def handle_event("reboot", _params, %{assigns: %{current_scope: scope}} = socket) do
              {:noreply, Map.put(socket, :seen, scope.role)}
            end
          end
        )

      assert {:noreply, %{seen: :admin}} = module.handle_event("reboot", %{}, socket(:admin))
    end

    test "requires_membership/0 refuses a scope without a role in the org" do
      module =
        compile(
          quote do
            use NervesHubWeb.AuthorizationDeclared, handle_event: 3

            @decorate requires_membership()
            def handle_event("page", _params, socket), do: {:noreply, socket}
          end
        )

      assert_raise NervesHubWeb.UnauthorizedError, fn -> module.handle_event("page", %{}, socket(nil)) end
      assert {:noreply, _} = module.handle_event("page", %{}, socket(:view))
    end

    test "requires_no_permission/0 and authorizes_in_body/1 check nothing" do
      module =
        compile(
          quote do
            use NervesHubWeb.AuthorizationDeclared, handle_event: 3

            @decorate requires_no_permission()
            def handle_event("open", _params, socket), do: {:noreply, socket}

            @decorate authorizes_in_body(:checked_below)
            def handle_event("save", _params, socket), do: {:noreply, socket}
          end
        )

      assert {:noreply, _} = module.handle_event("open", %{}, socket(nil))
      assert {:noreply, _} = module.handle_event("save", %{}, socket(nil))
    end

    test "a permission that doesn't exist does not compile" do
      assert_raise ArgumentError, ~r/:"device:explode", which is not a permission/, fn ->
        compile(
          quote do
            use NervesHubWeb.AuthorizationDeclared, handle_event: 3

            @decorate requires_permission(:"device:explode")
            def handle_event("explode", _params, socket), do: {:noreply, socket}
          end
        )
      end
    end

    test "a check needs the socket bound to a variable" do
      assert_raise ArgumentError, ~r/has to bind its socket to a variable/, fn ->
        compile(
          quote do
            use NervesHubWeb.AuthorizationDeclared, handle_event: 3

            @decorate requires_membership()
            def handle_event("page", _params, %{assigns: _}), do: :ok
          end
        )
      end
    end

    test "has to come before anything else that uses the decorator library" do
      assert_raise CompileError, ~r/use NervesHubWeb.AuthorizationDeclared before anything else/, fn ->
        compile(
          quote do
            use NervesHubWeb.AuthDecorator
            use NervesHubWeb.AuthorizationDeclared, handle_event: 3
          end
        )
      end
    end
  end

  describe "controller actions" do
    # From source rather than quoted: a plug's guard refers to `action`, which
    # has to be the variable Phoenix binds, not one hygiene renames.
    defp compile_controller(body) do
      name = "#{inspect(__MODULE__)}.C#{System.unique_integer([:positive])}"

      [{module, _}] =
        Code.compile_string("""
        defmodule #{name} do
          use NervesHubWeb, :api_controller

        #{body}
        end
        """)

      module
    end

    test "an action no authorization plug covers does not compile" do
      assert_raise CompileError, ~r/has actions no authorization plug covers: :delete/, fn ->
        compile_controller("""
          plug(:require_membership when action in [:show])

          def show(conn, _params), do: conn
          def delete(conn, _params), do: conn
        """)
      end
    end

    test "actions covered by any of the authorization plugs compile" do
      module =
        compile_controller("""
          plug(:require_membership when action in [:show])
          plug(:require_permission, :"device:delete" when action == :delete)
          plug(:require_no_permission, :signs_the_user_in when action not in [:show, :delete])
          plug(:load_thing)

          def show(conn, _params), do: conn
          def delete(conn, _params), do: conn
          def login(conn, _params), do: conn

          # A function plug, not an action.
          def load_thing(conn, _opts), do: conn
        """)

      assert function_exported?(module, :login, 2)
    end

    test "a guard that doesn't say which actions it covers does not compile" do
      assert_raise CompileError, ~r/does not say which actions it covers/, fn ->
        compile_controller("""
          plug(:require_membership when is_atom(action))

          def show(conn, _params), do: conn
        """)
      end
    end
  end
end
