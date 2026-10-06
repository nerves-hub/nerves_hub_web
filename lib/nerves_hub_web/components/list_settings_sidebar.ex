defmodule NervesHubWeb.Components.ListSettingsSidebar do
  use NervesHubWeb, :component

  alias NervesHub.Accounts
  alias Phoenix.LiveView.JS

  attr(:available_columns, :list, required: true)
  attr(:selected_columns, :list, required: true)
  attr(:on_update, :any, default: "update-settings")

  def render(assigns) do
    params = Map.new(assigns.available_columns, fn key -> {to_string(key), false} end)

    assigns = assign(assigns, :form, to_form(params))

    assigns =
      update(assigns, :selected_columns, fn selected_columns ->
        Enum.map(selected_columns || [], &Kernel.to_string/1)
      end)

    ~H"""
    <div class="pointer-events-none fixed inset-y-0 right-0 z-40 flex max-w-full pl-10 sm:pl-16">
      <div
        id="settings-sidebar"
        class="pointer-events-auto mt-[55px] hidden h-full w-screen max-w-80 flex-col border-t border-l border-base-700 bg-surface-muted shadow-filter-slider transition-transform"
        phx-window-keydown={hide_settings_sidebar()}
        phx-key="escape"
      >
        <div class="h-0 flex-1 overflow-y-auto">
          <div class="flex h-14 items-center border-b border-base-700 px-4 py-3">
            <h4 class="text-base font-semibold">Settings</h4>

            <button class="ml-auto cursor-pointer p-1.5" type="button" phx-click={hide_settings_sidebar()}>
              <span class="lucide-x--light size-5 text-base-300" />
            </button>
          </div>

          <div class="flex flex-col border-base-700 px-4 py-3">
            <span>Customize which columns you would like to see listed.</span>
            <.form :let={f} id="settings-form" for={@form} phx-change={@on_update}>
              <div :for={column <- @available_columns} class="mt-6">
                <.input field={f[column]} type="checkbox" label={to_column_name(column)} checked={selected?(column, @selected_columns)} />
              </div>
            </.form>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def show_column?(nil, _column_set, _column) do
    true
  end

  def show_column?(display_preferences, column_set, column) do
    Map.get(display_preferences, column_set)
    |> case do
      nil -> true
      selected_columns -> column in selected_columns
    end
  end

  def update_displayed_columns(user, column_set, params) do
    selected_columns =
      Enum.reject(params, fn {col, selected?} ->
        String.starts_with?(col, "_") || selected? != "true"
      end)
      |> Enum.map(fn {k, _} -> k end)

    Accounts.update_user_default_columns(user, column_set, selected_columns)
  end

  defp to_column_name(column) do
    to_string(column)
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp selected?(column, selected_columns) do
    if Enum.empty?(selected_columns) do
      true
    else
      to_string(column) in selected_columns
    end
  end

  defp hide_settings_sidebar() do
    JS.hide(
      to: "#settings-sidebar",
      transition: {"transition-transform duration-150 ease-in-out", "translate-x-0", "translate-x-full"},
      time: 150,
      blocking: false
    )
  end

  def show_settings_sidebar() do
    JS.show(
      to: "#settings-sidebar",
      display: "flex",
      transition: {"transition-transform duration-150 ease-in-out", "translate-x-full", "translate-x-0"},
      time: 150,
      blocking: false
    )
  end
end
