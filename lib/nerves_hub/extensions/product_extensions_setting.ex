defmodule NervesHub.Extensions.ProductExtensionsSetting do
  use Ecto.Schema
  import Ecto.Changeset
  @behaviour Access

  @primary_key false
  embedded_schema do
    field(:health, :boolean, default: false)
    field(:geo, :boolean, default: false)
    field(:local_shell, :boolean, default: false)
    field(:logging, :boolean, default: false)
  end

  def changeset(setting, params) do
    setting
    |> cast(params, [:health, :geo, :local_shell, :logging])
  end

  @impl Access
  defdelegate fetch(struct, key), to: Map
  @impl Access
  defdelegate pop(data, key), to: Map
  @impl Access
  defdelegate get_and_update(data, key, function), to: Map
end
