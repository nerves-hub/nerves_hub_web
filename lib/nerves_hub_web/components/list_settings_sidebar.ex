defmodule NervesHubWeb.Components.ListSettingsSidebar do
  use NervesHubWeb, :component

  alias NervesHub.Accounts.User
  alias NervesHub.Repo
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
        class="bg-surface-muted border-base-700 shadow-filter-slider pointer-events-auto mt-[55px] hidden h-full w-screen max-w-80 flex-col border-t border-l transition-transform"
        phx-window-keydown={hide_settings_sidebar()}
        phx-key="escape"
      >
        <div class="h-0 flex-1 overflow-y-auto">
          <div class="border-base-700 flex h-14 items-center border-b px-4 py-3">
            <h4 class="text-base font-semibold">Settings</h4>

            <button class="ml-auto cursor-pointer p-1.5" type="button" phx-click={hide_settings_sidebar()}>
              <span class="lucide-x--light text-base-300 size-5" />
            </button>
          </div>

          <div class="border-base-700 flex flex-col px-4 py-3">
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

    user =
      User.update_selected_default_columns_changeset(user, column_set, selected_columns)

    Repo.update(user)
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
