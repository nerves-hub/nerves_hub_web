defmodule NervesHubWeb.LucideIconsTest do
  @moduledoc """
  Checks that every `lucide-<icon>[--<weight>]` class has an icon to draw.

  `assets/vendor/lucideicons.js` generates a class for each SVG in
  `deps/lucide/icons` and nothing else, so a class naming an icon Lucide
  doesn't ship (often one it renamed in a release we've since upgraded to)
  produces no CSS and renders as nothing.
  """

  use ExUnit.Case, async: true

  @root Path.expand("../..", __DIR__)
  @icons_dir Path.join(@root, "deps/lucide/icons")
  @app_css Path.join(@root, "assets/css/app.css")

  # The weight suffixes assets/vendor/lucideicons.js generates, besides none.
  @weights ~w(verythin thin light semilight semibold bold)

  @class ~r/(?<![a-z0-9-])lucide-([a-z0-9]+(?:-[a-z0-9]+)*)(?:--([a-z0-9]+))?/

  test "every lucide class names an icon and a weight the Tailwind plugin generates" do
    icons =
      @icons_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".svg"))
      |> MapSet.new(&Path.rootname/1)

    problems =
      Enum.flat_map(lucide_classes(), fn {location, class, icon, weight} ->
        case problem(icons, icon, weight) do
          nil -> []
          problem -> ["#{location}: #{class} #{problem}"]
        end
      end)

    assert problems == [], """
    These lucide classes generate no CSS, so they render as nothing:

    #{Enum.join(problems, "\n")}
    """
  end

  defp problem(icons, icon, weight) do
    cond do
      not MapSet.member?(icons, icon) ->
        "has no #{icon}.svg in deps/lucide/icons#{renamed_hint(icon)}"

      weight not in [nil | @weights] ->
        "has a weight lucideicons.js doesn't generate (use one of #{Enum.join(@weights, ", ")})"

      true ->
        nil
    end
  end

  # Lucide lists an icon's old names as aliases in its JSON metadata.
  defp renamed_hint(icon) do
    renamed_to =
      @icons_dir
      |> Path.join("*.json")
      |> Path.wildcard()
      |> Enum.find(fn path ->
        path
        |> File.read!()
        |> JSON.decode!()
        |> Map.get("aliases", [])
        |> Enum.any?(&(alias_name(&1) == icon))
      end)

    if renamed_to, do: " (Lucide renamed it to #{Path.basename(renamed_to, ".json")})", else: ""
  end

  defp alias_name(%{"name" => name}), do: name
  defp alias_name(name), do: name

  # Scans the same directories Tailwind does, from the @source lines in app.css.
  defp lucide_classes() do
    sources = Regex.scan(~r/^@source "([^"]+)";/m, File.read!(@app_css), capture: :all_but_first)
    assert sources != [], "found no @source lines in #{@app_css}"

    for [source] <- sources,
        path <- Path.wildcard(Path.join([Path.dirname(@app_css), source, "**", "*"])),
        File.regular?(path),
        {line, number} <- path |> File.read!() |> String.split("\n") |> Enum.with_index(1),
        [class, icon | weight] <- Regex.scan(@class, line) do
      {"#{Path.relative_to(path, @root)}:#{number}", class, icon, List.first(weight)}
    end
  end
end
