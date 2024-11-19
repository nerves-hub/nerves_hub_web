defmodule NervesHub.Features.FeaturesSetting do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field(:health, :boolean, default: nil)
    field(:geo, :boolean, default: nil)
  end

  def changeset(setting, params) do
    setting
    |> cast(params, [:health, :geo])
  end
end
