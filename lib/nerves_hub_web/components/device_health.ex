defmodule NervesHubWeb.Components.DeviceHealth do
  use NervesHubWeb, :component

  def health_section(assigns) do
    ~H"""
    <tr :for={{key, value} <- @data} :if={is_map(@data)}>
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
