defmodule NervesHubWeb.ControllerAuthorizationDeclared do
  @moduledoc """
  Refuses to compile a controller with an action that no authorization plug
  covers.

  Every public action has to be named, or covered by a plug with no guard, in
  at least one of these from `NervesHubWeb.Helpers.PermissionPlugs`:

      plug(:require_permission, :"device:update" when action in [:update])
      plug(:require_membership when action in [:index, :show])
      plug(:require_no_permission, :signs_the_user_in when action in [:new, :create])

  `require_no_permission/2` checks nothing; its option says why nothing needs
  checking, for actions outside any organization or ones the request itself
  proves (a signed Slack request, a password reset token).

  A plug's guard has to be one this can read: none, `action in [...]`,
  `action not in [...]` or `action == ...`. Anything else does not compile
  either, as there is no telling which actions it covers. A
  `require_no_permission` plug has to name its actions, so an action added
  later isn't exempt without anyone saying so.

  `use NervesHubWeb, :controller` and `:api_controller` bring this in.
  """

  @authorization_plugs [:require_permission, :require_membership, :require_no_permission]

  # Defined by Phoenix.Controller, not actions.
  @not_actions [call: 2, action: 2]

  defmacro __using__(_opts) do
    quote do
      @before_compile NervesHubWeb.ControllerAuthorizationDeclared
    end
  end

  defmacro __before_compile__(env) do
    plugs = Module.get_attribute(env.module, :plugs) || []
    function_plugs = for {plug, _opts, _guards} <- plugs, is_atom(plug), do: {plug, 2}

    actions =
      for {name, 2} = action <- Module.definitions_in(env.module, :def),
          action not in @not_actions,
          action not in function_plugs,
          do: name

    covered =
      for {plug, _opts, guards} <- plugs, plug in @authorization_plugs, reduce: MapSet.new() do
        acc -> MapSet.union(acc, MapSet.new(covered_actions(guards, actions, env, plug)))
      end

    actions
    |> Enum.reject(&MapSet.member?(covered, &1))
    |> Enum.sort()
    |> case do
      [] ->
        nil

      undeclared ->
        raise CompileError,
          file: env.file,
          line: 0,
          description: """
          #{inspect(env.module)} has actions no authorization plug covers: #{Enum.map_join(undeclared, ", ", &inspect/1)}

          Name each in one of:

              plug(:require_permission, :"device:update" when action in [...])
              plug(:require_membership when action in [...])
              plug(:require_no_permission, :reason when action in [...])

          See NervesHubWeb.ControllerAuthorizationDeclared.
          """
    end
  end

  defp covered_actions(true, _actions, env, :require_no_permission) do
    raise CompileError,
      file: env.file,
      line: 0,
      description:
        "#{inspect(env.module)} has a :require_no_permission plug with no guard, which would " <>
          "exempt every action, including ones added later. Name them: `when action in [...]`."
  end

  defp covered_actions(true, actions, _env, _plug), do: actions
  defp covered_actions({:in, _, [{:action, _, _}, list]}, _actions, _env, _plug) when is_list(list), do: list

  defp covered_actions({:not, _, [{:in, _, [{:action, _, _}, list]}]}, actions, _env, _plug) when is_list(list),
    do: actions -- list

  defp covered_actions({:==, _, [{:action, _, _}, action]}, _actions, _env, _plug) when is_atom(action), do: [action]

  defp covered_actions(guards, _actions, env, plug) do
    raise CompileError,
      file: env.file,
      line: 0,
      description:
        "#{inspect(env.module)} guards #{inspect(plug)} with `when #{Macro.to_string(guards)}`, " <>
          "which does not say which actions it covers. Use `when action in [...]`."
  end
end
