defmodule NervesHubWWWWeb.DeviceView do
  use NervesHubWWWWeb, :view

  alias NervesHubDevice.Presence

  import NervesHubWWWWeb.LayoutView, only: [health_status_icon: 1]

  def architecture_options do
    [
      "aarch64",
      "arm",
      "mipsel",
      "x86",
      "x86_atom",
      "x86_64"
    ]
  end

  def devices_table_header(title, value, current_sort, sort_direction \\ :asc)

  def devices_table_header(title, value, current_sort, sort_direction)
      when value == current_sort do
    caret_class = if sort_direction == :asc, do: "up", else: "down"

    content_tag(:th, phx_click: "sort", phx_value_sort: value, class: "pointer sort-selected") do
      [title, content_tag(:i, "", class: "icon-caret icon-caret-#{caret_class}")]
    end
  end

  def devices_table_header(title, value, _current_sort, _sort_direction) do
    content_tag(:th, title, phx_click: "sort", phx_value_sort: value, class: "pointer")
  end

  def platform_options do
    [
      "bbb",
      "ev3",
      "qemu_arm",
      "rpi",
      "rpi0",
      "rpi2",
      "rpi3",
      "smartrent_hub",
      "x86_64"
    ]
  end

  def tags_to_string(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.get_field(:tags)
    |> tags_to_string()
  end

  def tags_to_string(%{tags: tags}), do: tags_to_string(tags)
  def tags_to_string(tags) when is_list(tags), do: Enum.join(tags, ",")
  def tags_to_string(tags), do: tags

  defdelegate device_status(device), to: Presence
  
  def take_device_tags(device, amount) do
    Enum.take(device.tags, amount)
  end
  
  def count_device_tags(device) do
    Enum.count(device.tags)
  end
end
