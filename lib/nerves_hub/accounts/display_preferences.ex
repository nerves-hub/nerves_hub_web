defmodule NervesHub.Accounts.User.DisplayPreferences do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Accounts.User.DisplayPreferences

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

  def device_list_columns(), do: @all_device_list_columns

  def deployment_group_list_columns(), do: @all_deployment_group_list_columns

  embedded_schema do
    field(:device_list_columns, {:array, Ecto.Enum},
      values: @all_device_list_columns,
      default: nil
    )

    field(:deployment_group_list_columns, {:array, Ecto.Enum},
      values: @all_deployment_group_list_columns,
      default: nil
    )
  end

  def changeset(%DisplayPreferences{} = preferences, attrs \\ %{}) do
    cast(preferences, attrs, [:device_list_columns, :deployment_group_list_columns])
  end
end
