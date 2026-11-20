defmodule NervesHubWeb.Components.Switch do
  @moduledoc """
  A checkbox drawn as a switch, for settings that take effect as soon as they
  are flipped (the device page's Settings tab and product settings), or that a
  form saves with the rest of its fields, as the release dialogs do.
  """
  use Phoenix.Component

  attr(:id, :string, required: true)
  attr(:name, :string, required: true)
  attr(:checked, :boolean, required: true)
  attr(:disabled, :boolean, default: false)
  attr(:rest, :global, include: ~w(value form))

  @doc """
  Acts through the `phx-click` it is given, so it needs no form. In a form,
  give it `value="true"` after a hidden input of the same name holding
  `"false"`, so the form sends either.
  """
  def switch(assigns) do
    ~H"""
    <span class="relative inline-flex h-4.5 w-8 shrink-0">
      <input
        type="checkbox"
        role="switch"
        id={@id}
        name={@name}
        checked={@checked}
        disabled={@disabled}
        class={[
          "peer size-full cursor-pointer appearance-none rounded-full border-0 bg-line-strong bg-none p-0 text-primary transition-colors light:text-indigo-600",
          "checked:bg-current checked:bg-none focus:ring-0 focus:ring-offset-0",
          "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus-ring",
          "disabled:cursor-not-allowed disabled:opacity-60 [&:disabled:not(:checked)]:bg-line-default"
        ]}
        {@rest}
      />
      <span
        class="pointer-events-none absolute top-0.5 left-0.5 size-3.5 rounded-full bg-white shadow-control transition-transform peer-checked:translate-x-3.5"
        aria-hidden="true"
      ></span>
    </span>
    """
  end
end
