defmodule NervesHub.Accounts.User.DisplayPreferences do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Accounts.User.DisplayPreferences
  alias NervesHub.Types.KnownAtom
  alias NervesHub.Types.KnownAtoms

  @all_device_list_columns [
    :health,
    :firmware,
    :platform,
    :connected_info,
    :deployment_group,
    :tags
  ]

  @all_deployment_group_list_columns [
    :platform,
    :architecture,
    :device_count,
    :release_count,
    :firmware_version,
    :tags,
    :version_constraint
  ]

  # The boxes on the device page's details tab, and the column each one sits
  # in until the user moves it. The order here is the default top-to-bottom
  # order within each column.
  @default_device_details_layout [
    left: [:health, :alarms, :general_info, :deployment],
    right: [:location, :network_identities, :support_scripts]
  ]

  @all_device_details_boxes Enum.flat_map(@default_device_details_layout, &elem(&1, 1))

  # The base map styles the user can pick for location maps. The web layer
  # maps each to a Mapbox style.
  @all_map_styles [:streets, :outdoors, :light, :dark, :satellite, :satellite_streets]

  def device_list_columns(), do: @all_device_list_columns

  def device_details_boxes(), do: @all_device_details_boxes

  def deployment_group_list_columns(), do: @all_deployment_group_list_columns

  def map_styles(), do: @all_map_styles

  @type t() :: %__MODULE__{}

  embedded_schema do
    # The columns the user has chosen to show on the device and deployment
    # group lists. Nil shows every column.
    #
    # Removing a column from `@all_device_list_columns` or
    # `@all_deployment_group_list_columns` is safe: `KnownAtoms` skips names it
    # no longer knows when loading, and the user's next change to their
    # columns saves the list without them. Unlike `Ecto.Enum`, a stale name
    # doesn't stop the user loading. To clear stale names from the database
    # straight away, add an update to the PR that removes the column.
    field(:device_list_columns, KnownAtoms, values: @all_device_list_columns, default: nil)
    field(:deployment_group_list_columns, KnownAtoms, values: @all_deployment_group_list_columns, default: nil)

    # Where the user has dragged the details tab's boxes to, top to bottom.
    # Both nil until they first move one.
    #
    # Removing a box from `@default_device_details_layout` is safe: `KnownAtoms`
    # skips names it no longer knows when loading, and the user's next drag
    # saves their layout without them. Unlike `Ecto.Enum`, a stale name doesn't
    # stop the user loading. To clear stale names from the database straight
    # away, add an update to the PR that removes the box.
    field(:device_details_left, KnownAtoms, values: @all_device_details_boxes, default: nil)
    field(:device_details_right, KnownAtoms, values: @all_device_details_boxes, default: nil)

    # The style the user has picked for location maps. Nil follows the light
    # or dark theme.
    #
    # Removing a style from `@all_map_styles` is safe: `KnownAtom` loads a name
    # it no longer knows as nil, so the user's maps go back to following the
    # theme.
    field(:map_style, KnownAtom, values: @all_map_styles, default: nil)
  end

  def changeset(%DisplayPreferences{} = preferences, attrs \\ %{}) do
    preferences
    |> cast(attrs, [
      :device_list_columns,
      :deployment_group_list_columns,
      :device_details_left,
      :device_details_right,
      :map_style
    ])
    |> validate_device_details_layout()
  end

  @doc """
  The details tab's boxes as `{left, right}`, each listed top to bottom.

  The default layout when the user hasn't arranged the boxes. A box added
  after they saved theirs goes at the bottom of its default column, so a new
  box shows up without anyone having to reset their layout.
  """
  @spec device_details_layout(t() | nil) :: {[atom()], [atom()]}
  def device_details_layout(%DisplayPreferences{device_details_left: left, device_details_right: right})
      when is_list(left) and is_list(right) do
    placed = left ++ right

    unplaced = fn column ->
      Enum.reject(@default_device_details_layout[column], &(&1 in placed))
    end

    {left ++ unplaced.(:left), right ++ unplaced.(:right)}
  end

  def device_details_layout(_preferences) do
    {@default_device_details_layout[:left], @default_device_details_layout[:right]}
  end

  @doc """
  Whether the user has arranged the details tab's boxes themselves.
  """
  @spec custom_device_details_layout?(t() | nil) :: boolean()
  def custom_device_details_layout?(%DisplayPreferences{device_details_left: left, device_details_right: right}),
    do: is_list(left) and is_list(right)

  def custom_device_details_layout?(_preferences), do: false

  @doc """
  The style the user has picked for location maps, or nil to follow the light
  or dark theme.
  """
  @spec map_style(t() | nil) :: atom() | nil
  def map_style(%DisplayPreferences{map_style: map_style}), do: map_style
  def map_style(_preferences), do: nil

  # A box can only be in one place.
  defp validate_device_details_layout(changeset) do
    left = get_field(changeset, :device_details_left) || []
    right = get_field(changeset, :device_details_right) || []
    boxes = left ++ right

    if boxes == Enum.uniq(boxes) do
      changeset
    else
      add_error(changeset, :device_details_left, "lists a box more than once")
    end
  end
end
