defmodule NervesHubWeb.AuthorizationDeclared do
  @moduledoc """
  Refuses to compile a LiveView, LiveComponent or device page tab in which a
  callback a client can drive does not say what authorization it needs.

  A browser can send any event to a LiveView it has open, whether or not the
  page shows the button for it, so hiding a control is never the check.
  Every clause of these callbacks has to carry one of the decorators in
  `NervesHubWeb.AuthDecorator`:

    * LiveViews: `mount/3`, `handle_params/3`, `handle_event/3` and
      `handle_progress/3`.
    * LiveComponents: `handle_event/3` and `handle_progress/3`.
    * Device page tabs: `hooked_event/3`, which sees the page's events before
      the LiveView does, and `handle_progress/3`.

  `use NervesHubWeb, :live_view` (and `:live_component`, `tab_component:`)
  brings this in. A module lists the callbacks to check:

      use NervesHubWeb.AuthorizationDeclared, handle_event: 3

  ## How it hooks in

  The decorator library records each clause's `@decorate` attributes as it
  is defined, and in its `@before_compile` defines the decorated functions
  again. So this module:

    * registers its `@on_definition` hook after the library's. Hooks run last
      registered first, so this one still sees `@decorate` before the library
      clears it.
    * registers its `@before_compile` before the library's, so the check runs
      before the library redefines anything. It then stops recording: the
      redefinitions carry no `@decorate` of their own.

  Both orders are set here, in `__using__/1`, which is why it has to come
  before anything else in the module that uses the decorator library. Were
  either order to change, every decorated clause would be reported as
  undeclared, so it cannot go wrong quietly.
  """

  alias NervesHubWeb.AuthDecorator

  @decorators [:requires_permission, :requires_membership, :requires_no_permission, :authorizes_in_body]

  defmacro __using__(callbacks) do
    quote do
      require NervesHubWeb.AuthDecorator

      if Module.get_attribute(__MODULE__, :has_been_decorated) do
        raise CompileError,
          file: __ENV__.file,
          line: __ENV__.line,
          description: "use NervesHubWeb.AuthorizationDeclared before anything else that uses the decorator library"
      end

      Module.put_attribute(__MODULE__, :authorization_callbacks, unquote(callbacks))
      Module.register_attribute(__MODULE__, :authorization_undeclared, accumulate: true)
      Module.put_attribute(__MODULE__, :authorization_checked?, false)

      # The order of these three is the point, see the moduledoc. They are
      # written as calls, and `use` as what it expands to, because the
      # formatter hoists `use` and module attributes to the top of a block.
      Module.put_attribute(__MODULE__, :before_compile, {NervesHubWeb.AuthorizationDeclared, :__before_compile__})
      NervesHubWeb.AuthDecorator.__using__([])
      Module.put_attribute(__MODULE__, :on_definition, {NervesHubWeb.AuthorizationDeclared, :on_definition})
    end
  end

  @doc false
  def on_definition(env, :def, name, args, _guards, body) when not is_nil(body) do
    module = env.module

    with false <- Module.get_attribute(module, :authorization_checked?),
         true <- {name, length(args)} in Module.get_attribute(module, :authorization_callbacks),
         false <- declared?(Module.get_attribute(module, :decorate)) do
      Module.put_attribute(module, :authorization_undeclared, {name, args, env.line})
    end

    :ok
  end

  def on_definition(_env, _kind, _name, _args, _guards, _body), do: :ok

  defp declared?(decorators) do
    Enum.any?(decorators || [], fn
      {AuthDecorator, decorator, _args} -> decorator in @decorators
      _other -> false
    end)
  end

  defmacro __before_compile__(env) do
    Module.put_attribute(env.module, :authorization_checked?, true)

    env.module
    |> Module.get_attribute(:authorization_undeclared)
    |> Enum.reverse()
    |> case do
      [] ->
        nil

      [{name, args, line} | _] = undeclared ->
        clauses =
          Enum.map_join(undeclared, "\n", fn {name, args, line} ->
            "  * line #{line}: #{name}(#{Enum.map_join(args, ", ", &Macro.to_string/1)})"
          end)

        raise CompileError,
          file: env.file,
          line: line,
          description: """
          #{name}/#{length(args)} in #{inspect(env.module)} does not say what authorization it needs:

          #{clauses}

          A client can send these whether or not the page shows the control, so every
          clause needs one of:

              @decorate requires_permission(:"device:update")
              @decorate requires_membership()
              @decorate requires_no_permission()
              @decorate authorizes_in_body(:reason)

          See NervesHubWeb.AuthDecorator for which one fits.
          """
    end
  end
end
