defmodule NervesHubWeb.LiveView do
  @moduledoc """
  Switches in a -new.html.heex template if the new_ui == true in compile-time config.
  """
  defmacro __using__(opts) do
    quote do
      if Application.compile_env(:nerves_hub, :new_ui) == true do
        @before_compile NervesHubWeb.LiveView
      end
      use NervesHubWeb, :updated_live_view
    end
  end

  defmacro __before_compile__(%{file: file, module: module}) do
    root = Path.dirname(file)
    # This is what Phoenix does
    filename =
      module
      |> Module.split()
      |> List.last()
      |> Macro.underscore()
      |> Kernel.<>("-new.html")
    templates = Phoenix.Template.find_all(root, filename)
    case templates do
      [template] ->
        IO.inspect(template, label: "found?")
        ext = template |> Path.extname() |> String.trim_leading(".") |> String.to_atom()
        engine = Map.fetch!(Phoenix.Template.engines(), ext)
        ast = engine.compile(template, filename)
        IO.inspect(ast, label: "ast")

        quote do
          @file unquote(template)
          @external_resource unquote(template)
          def render(var!(assigns)) when is_map(var!(assigns)) do
            unquote(ast)
          end
        end
      _ ->
        nil
    end
  end
end
