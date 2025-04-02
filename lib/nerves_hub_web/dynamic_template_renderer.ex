defmodule NervesHubWeb.DynamicTemplateRenderer do
  @moduledoc """
  Switches in a -new.html.heex template if `new_ui` has been enabled in `runtime.exs`
  and the template exists.
  """

  require Logger

  defmacro __before_compile__(%{module: module, file: file} = env) do
    render? = Module.defines?(module, {:render, 1})
    root = Path.dirname(file)
    filename = template_filename(module)
    templates = Phoenix.Template.find_all(root, filename)

    case {render?, templates} do
      {true, [template | _]} ->
        IO.warn(
          "ignoring template #{inspect(template)} because the LiveView " <>
            "#{inspect(env.module)} defines a render/1 function",
          Macro.Env.stacktrace(env)
        )

        :ok

      {true, []} ->
        :ok

      {false, [template]} ->
        custom_multi_template_processing(template, filename, module, root)

      {false, [_ | _]} ->
        IO.warn(
          "multiple templates were found for #{inspect(env.module)}: #{inspect(templates)}",
          Macro.Env.stacktrace(env)
        )

        :ok

      {false, []} ->
        template = Path.join(root, filename <> ".heex")

        quote do
          @external_resource unquote(template)
        end
    end
  end

  defp custom_multi_template_processing(template, filename, module, root) do
    ext = template |> Path.extname() |> String.trim_leading(".") |> String.to_atom()
    engine = Map.fetch!(Phoenix.Template.engines(), ext)
    ast = engine.compile(template, filename)

    new_filename = template_filename(module, "-new")
    new_templates = Phoenix.Template.find_all(root, new_filename)

    case new_templates do
      [new_template] ->
        new_ext =
          new_template |> Path.extname() |> String.trim_leading(".") |> String.to_atom()

        new_engine = Map.fetch!(Phoenix.Template.engines(), new_ext)
        new_ast = new_engine.compile(new_template, filename)

        quote do
          @file unquote(template)
          @external_resource unquote(template)
          @external_resource unquote(new_template)
          def render(var!(assigns)) when is_map(var!(assigns)) do
            if Application.get_env(:nerves_hub, :new_ui) && var!(assigns)[:new_ui] do
              unquote(new_ast)
            else
              unquote(ast)
            end
          end
        end

      _ ->
        quote do
          @file unquote(template)
          @external_resource unquote(template)
          def render(var!(assigns)) when is_map(var!(assigns)) do
            unquote(ast)
          end
        end
    end
  end

  defp template_filename(module, suffix \\ "") do
    module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> Kernel.<>(suffix)
    |> Kernel.<>(".html")
  end
end
