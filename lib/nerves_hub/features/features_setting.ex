defmodule NervesHub.Features.FeaturesSetting do
  use Ecto.Schema
  import Ecto.Changeset

  @valid_features [:health, :geo]

  @primary_key false
  embedded_schema do
    # a feature can be enabled, disabled or unset, unset means it is missing in both listings
    field(:enabled, {:array, Ecto.Enum}, values: @valid_features, default: [])
    field(:disabled, {:array, Ecto.Enum}, values: @valid_features, default: [])
  end

  def changeset(setting, params) do
    setting
    |> cast(params, [:enabled, :disabled])
    |> then(fn changeset ->
      enabled = get_field(changeset, :enabled, [])
      disabled = get_field(changeset, :disabled, [])
      # Remove any enabled that are now in disabled, we prioritize disabling
      enabled = Enum.reject(enabled, & &1 in disabled)
      change(changeset, enabled: enabled, disabled: disabled)
    end)
  end
end
