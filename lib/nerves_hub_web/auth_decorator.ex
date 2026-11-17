defmodule NervesHubWeb.AuthDecorator do
  @moduledoc """
  The decorators a LiveView, LiveComponent or device page tab uses to say what
  a client-driven callback needs before it may run.

    * `@decorate requires_permission(:"device:update")` refuses unless the
      scope holds the permission, before the body runs. The permission has to
      be one `NervesHub.Accounts.Permissions` defines, or the module won't
      compile.
    * `@decorate requires_membership()` refuses unless the user is a member
      of the scope's organization. For anything on an organization's pages
      that any member may do: reading, paging, filtering, opening a form.
    * `@decorate requires_no_permission()` checks nothing. For pages outside
      any organization (the account page, the organization list), where
      being signed in is enough, and for a hook clause that does nothing but
      pass the event on.
    * `@decorate authorizes_in_body(:reason)` checks nothing here, and says
      the body does: the permission depends on what the body loads or on the
      params. The reason is for whoever reads it next.

  A refusal raises `NervesHubWeb.UnauthorizedError`, exactly as calling
  `NervesHubWeb.Helpers.Authorization.authorized!/2` at the top of the body
  would.

  The checks read `socket.assigns.current_scope`, so the socket argument has
  to be bound to a variable (`%{assigns: ...} = socket` works), and a
  LiveComponent that checks has to be given the scope by whoever renders it.

  `NervesHubWeb.AuthorizationDeclared` makes these mandatory on every clause
  of the callbacks a client can drive.
  """

  use Decorator.Define,
    requires_permission: 1,
    requires_membership: 0,
    requires_no_permission: 0,
    authorizes_in_body: 1

  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.Permissions
  alias NervesHub.Accounts.Scope
  alias NervesHubWeb.Helpers.Authorization

  def requires_permission(permission, body, context) do
    if !Permissions.known?(permission) do
      raise ArgumentError,
            "#{inspect(context.module)}.#{context.name}/#{context.arity} requires #{inspect(permission)}, " <>
              "which is not a permission. See NervesHub.Accounts.Permissions."
    end

    socket = socket_var!(context)

    quote location: :keep do
      Authorization.authorized!(unquote(permission), unquote(socket).assigns.current_scope)
      unquote(body)
    end
  end

  def requires_membership(body, context) do
    socket = socket_var!(context)

    quote location: :keep do
      NervesHubWeb.AuthDecorator.member!(unquote(socket).assigns)
      unquote(body)
    end
  end

  def requires_no_permission(body, _context), do: body

  def authorizes_in_body(reason, body, context) do
    if !is_atom(reason) or is_nil(reason) do
      raise ArgumentError,
            "authorizes_in_body/1 on #{inspect(context.module)}.#{context.name}/#{context.arity} " <>
              "takes an atom saying where the check is, such as :permission_depends_on_params"
    end

    body
  end

  @doc false
  # The same test as `NervesHubWeb.Helpers.PermissionPlugs.require_membership/2`.
  def member!(%{current_scope: %Scope{org: %Org{}, role: role}}) when not is_nil(role), do: :ok
  def member!(_assigns), do: raise(NervesHubWeb.UnauthorizedError)

  # Every callback these decorate takes the socket last. The argument may be a
  # plain variable or a pattern bound to one (`%{...} = socket`). Unquoting the
  # pattern itself would match it again and rebind what it binds.
  defp socket_var!(%{args: args} = context) do
    case socket_var(List.last(args)) do
      nil ->
        raise ArgumentError,
              "#{inspect(context.module)}.#{context.name}/#{context.arity} has to bind its socket to a " <>
                "variable for the authorization check to read the scope, for example `%{assigns: ...} = socket`"

      var ->
        var
    end
  end

  defp socket_var({:=, _, [left, right]}), do: socket_var(left) || socket_var(right)

  defp socket_var({name, _, ctx} = var) when is_atom(name) and is_atom(ctx) do
    if !String.starts_with?(Atom.to_string(name), "_"), do: var
  end

  defp socket_var(_pattern), do: nil
end
