defmodule NervesHubWeb.Components.DeviceHealth do
  use NervesHubWeb, :component

  def health_section(assigns) do
    dbg(assigns)
    ~H"""
    <tr :if={is_map(@data)} :for={{key, value} <- @data}>
      <td style="text-transform: capitalize;"><%= String.replace(key, "_", " ") %></td>
      <td style="padding-left: 8px;">
      <%= cond do
            is_map(value) -> health_section(%{data: value})
            is_float(value) -> round(value)
            true -> to_string(value)
          end %>
      </td>
    </tr>
    """
  end
end
