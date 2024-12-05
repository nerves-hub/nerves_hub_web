defmodule NervesHubWeb.LiveView do
  @moduledoc """
  Switches in a -new.html.heex template if `new_ui` has been enabled in `runtime.exs`
  and the template exists.
  """

  require Logger

  defmacro __using__(opts) do
    # Expand layout if possible to avoid compile-time dependencies
    opts =
      with true <- Keyword.keyword?(opts),
           {layout, template} <- Keyword.get(opts, :layout) do
        layout = Macro.expand(layout, %{__CALLER__ | function: {:__live__, 0}})
        Keyword.replace!(opts, :layout, {layout, template})
      else
        _ -> opts
      end

    quote bind_quoted: [opts: opts] do
      import Phoenix.LiveView
      @behaviour Phoenix.LiveView
      @before_compile NervesHubWeb.DynamicTemplateRenderer

      @phoenix_live_opts opts
      Module.register_attribute(__MODULE__, :phoenix_live_mount, accumulate: true)
      @before_compile Phoenix.LiveView

      # Phoenix.Component must come last so its @before_compile runs last
      use Phoenix.Component, Keyword.take(opts, [:global_prefixes])
    end
  end
end
