defmodule NervesHubWeb.LiveView do
  @moduledoc """
  Switches in a -new.html.heex template if `new_ui` has been enabled in `runtime.exs`
  and the template exists.
  """

  require Logger

  defmacro __using__(_opts) do
    quote do
      @before_compile NervesHubWeb.LiveView

      use NervesHubWeb, :updated_live_view
    end
  end

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
        ext = template |> Path.extname() |> String.trim_leading(".") |> String.to_atom()
        engine = Map.fetch!(Phoenix.Template.engines(), ext)
        ast = engine.compile(template, filename)

        root = Path.dirname(file)

        new_filename = template_filename(module, "-new")

        templates = Phoenix.Template.find_all(root, new_filename)

        case templates do
          [new_template] ->
            Logger.info("Found New UI page: #{template}")
            new_ext = template |> Path.extname() |> String.trim_leading(".") |> String.to_atom()
            new_engine = Map.fetch!(Phoenix.Template.engines(), new_ext)
            new_ast = new_engine.compile(new_template, new_filename)

            quote do
              @file unquote(template)
              @external_resource unquote(template)
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

  defp template_filename(module, suffix \\ "") do
    module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> Kernel.<>(suffix)
    |> Kernel.<>(".html")
  end
end
