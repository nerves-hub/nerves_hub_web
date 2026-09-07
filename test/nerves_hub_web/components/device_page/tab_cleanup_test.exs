defmodule NervesHubWeb.Components.DevicePage.TabCleanupTest do
  @moduledoc """
  Guards the one rule `cleanup/0` has to follow.

  The device page attaches a `handle_params` hook for every tab in
  `NervesHubWeb.Live.Devices.Show`'s `@tab_components`, and each *inactive* tab's
  hook deletes the assigns its `cleanup/0` names. The hooks run in the order the
  tabs are listed, so a tab that cleans a key another tab **sets** will, whenever
  it happens to sit later in that list, delete the assign the active tab has just
  put there — and the failure surfaces as a `KeyError` inside an unrelated tab's
  render, a long way from the `cleanup/0` that caused it.

  That is not a hypothetical. `ErrorsTab` listed `:analytics_enabled` and
  `:streaming_enabled`, both of which `DataHistoryTab` sets from an earlier
  position, and thirteen unrelated tests failed on a crash in the Data History
  tab.

  So: **`cleanup/0` may only name assigns that tab alone uses.** A key two tabs
  share is one neither may clean — it costs a couple of retained assigns, which
  is a great deal cheaper than a trap that depends on list order.
  """

  use ExUnit.Case, async: true

  @source_dir "lib/nerves_hub_web/components/device_page"
  @namespace "Elixir.NervesHubWeb.Components.DevicePage."

  # Both spellings reach the same place: `assign(socket, :key, value)` and the
  # piped `|> assign(:key, value)`, which parses with the key as its first
  # argument because a pipe is still a pipe in the AST.
  @assign_functions [:assign, :assign_new, :assign_async]

  test "no tab's cleanup/0 names an assign another tab sets" do
    tabs = tab_modules()

    # A guard against the discovery silently finding nothing and passing: this
    # check is only worth anything if there are tabs to compare.
    assert length(tabs) > 1, "expected to discover several device page tabs, found #{inspect(tabs)}"

    assigned = Map.new(tabs, &{&1, assigned_keys(&1)})

    trespasses =
      for tab <- tabs,
          key <- tab.cleanup(),
          other <- tabs,
          other != tab,
          MapSet.member?(Map.fetch!(assigned, other), key),
          do: {tab, key, other}

    assert trespasses == [], failure_message(trespasses)
  end

  defp tab_modules() do
    {:ok, modules} = :application.get_key(:nerves_hub, :modules)

    modules
    |> Enum.filter(fn module ->
      # What makes a module a tab rather than something else living alongside one.
      String.starts_with?(Atom.to_string(module), @namespace) and Code.ensure_loaded?(module) and
        function_exported?(module, :cleanup, 0) and function_exported?(module, :hooked_params, 3)
    end)
    |> Enum.sort()
  end

  defp assigned_keys(module) do
    {_ast, keys} =
      module
      |> source_path()
      |> File.read!()
      |> Code.string_to_quoted!()
      |> Macro.prewalk(MapSet.new(), &collect_assign_key/2)

    keys
  end

  defp collect_assign_key({function, _meta, [key | _rest]} = node, acc)
       when function in @assign_functions and is_atom(key) do
    {node, MapSet.put(acc, key)}
  end

  defp collect_assign_key({function, _meta, [_socket, key | _rest]} = node, acc)
       when function in @assign_functions and is_atom(key) do
    {node, MapSet.put(acc, key)}
  end

  defp collect_assign_key(node, acc), do: {node, acc}

  defp source_path(module) do
    file =
      module
      |> Atom.to_string()
      |> String.replace_prefix(@namespace, "")
      |> Macro.underscore()

    Path.join(@source_dir, file <> ".ex")
  end

  defp failure_message(trespasses) do
    listed =
      Enum.map_join(trespasses, "\n", fn {tab, key, other} ->
        "  #{inspect(tab)}.cleanup/0 names #{inspect(key)}, which #{inspect(other)} assigns"
      end)

    """
    A tab's cleanup/0 may only name assigns that tab alone uses.

    #{listed}

    Every inactive tab's cleanup/0 runs on each handle_params, in the order the
    tabs appear in NervesHubWeb.Live.Devices.Show's @tab_components. Cleaning a
    key another tab sets deletes that tab's assign whenever the cleaning tab is
    listed later, and the crash lands in the other tab's render rather than here.

    Either drop the shared key from cleanup/0 and let it be retained, or give
    this tab's assign a name of its own.
    """
  end
end
