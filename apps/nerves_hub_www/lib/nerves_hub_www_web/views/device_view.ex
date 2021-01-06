defmodule NervesHubWWWWeb.DeviceView do
  use NervesHubWWWWeb, :view

  alias NervesHubDevice.Presence
  alias NervesHubWWWWeb.LayoutView.DateTimeFormat, as: DateTimeFormat

  import NervesHubWWWWeb.LayoutView,
    only: [pagination_links: 1, user_orgs: 1, user_org_products: 2]

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

  def display_status(status) when is_binary(status) do
    status
    |> String.split("-")
    |> Enum.join(" ")
  end

  def display_status(_), do: nil

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

  def selected?(filters, field, value), do: if(filters[field] == value, do: "selected")

  def move_alert(product_name) do
    """
    This will move the selected device(s) to the #{product_name} product

    Any existing firmware keys the devices may use will attempt to be migrated if they do not exist on the target organization.

    Moving devices may also trigger an update if there are matching deployments on the new product. It is up to the user to ensure any required firmware keys are on the device before migrating them to a new product with a new firmware or the device may fail to update.

    Do you wish to continue?
    """
  end
end
