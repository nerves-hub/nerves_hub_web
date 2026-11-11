defmodule NervesHubWeb.Access.AuthorizationDeclared do
  @moduledoc """
  Refuses to compile a module in which a client-reachable callback does not
  state its authorization.

  A module names the callbacks to check, as `{name, arity}` pairs:

      use NervesHubWeb.Access.AuthorizationDeclared, handle_event: 3

  This brings in the decorators of `NervesHubWeb.Access.AuthDecorator`, and
  every clause of the named callbacks then needs one of them. This is what
  makes it impossible to add an event handler and forget the access check: the
  check at run time, in the wrappers, only sees a handler once somebody
  triggers it.

  The order in `__using__/1` matters. The decorator library collects the
  definitions in `@decorated`, and in its own `@before_compile` callback
  deletes them and defines the decorated functions again, without decorators.
  The callback here has to run first, so it is registered first. Were the
  order to change, every decorated clause would be reported as undeclared, so
  it cannot go wrong quietly.
  """

  alias NervesHubWeb.Access.AuthDecorator

  defmacro __using__(callbacks) do
    # Written as calls, and not as `@before_compile` and `use` side by side, so
    # that a formatter which sorts module directives cannot swap them.
    register_check =
      quote do
        Module.put_attribute(__MODULE__, :authorization_required, unquote(callbacks))
        Module.put_attribute(__MODULE__, :before_compile, {unquote(__MODULE__), :__before_compile__})
      end

    decorators = quote(do: use(AuthDecorator))

    [register_check, decorators]
  end

  defmacro __before_compile__(env) do
    required = Module.get_attribute(env.module, :authorization_required)
    definitions = Module.get_attribute(env.module, :decorated) || []

    undeclared =
      for {_kind, name, args, guards, body, decorators, _attrs} <- Enum.reverse(definitions),
          {name, length(args)} in required,
          body != nil,
          not wrapper?(guards),
          not Enum.any?(decorators, &match?({AuthDecorator, _fun, _args}, &1)) do
        {name, args}
      end

    case undeclared do
      [] ->
        nil

      [{name, args} | _] ->
        clauses =
          Enum.map_join(undeclared, "\n", fn {name, args} ->
            "  * #{name}(#{Enum.map_join(args, ", ", &Macro.to_string/1)}) (line #{line(args, env)})"
          end)

        raise CompileError,
          file: env.file,
          line: line(args, env),
          description: """
          #{name}/#{length(args)} in #{inspect(env.module)} does not state its authorization:

          #{clauses}

          Every clause needs one of:

              @decorate requires_permission(:"device:list")
              @decorate requires_permission(:"device:update", on: :device)
              @decorate authorizes_in_body()
              @decorate requires_no_permission()
              @decorate special_permission(:reason)
          """
    end
  end

  # The clause the wrapper itself defines, see `NervesHubWeb.Access.AuthorizedLiveView`.
  defp wrapper?(guards) do
    {_ast, found?} =
      Macro.prewalk(guards, false, fn
        {:is_wrapped, _meta, [_private]} = ast, _found? -> {ast, true}
        ast, found? -> {ast, found?}
      end)

    found?
  end

  defp line(args, env) do
    {_ast, line} =
      Macro.prewalk(args, nil, fn
        {_name, meta, _args} = ast, nil when is_list(meta) -> {ast, meta[:line]}
        ast, line -> {ast, line}
      end)

    line || env.line
  end
end
