defmodule NervesHub.Features.Feature do
  use Ecto.Schema

  schema "features" do
    field(:description, :string)
    field(:key, Ecto.Enum, values: [:health, :geo])
    field(:name, :string)
  end
end
