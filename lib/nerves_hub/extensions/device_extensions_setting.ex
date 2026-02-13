defmodule NervesHub.Extensions.DeviceExtensionsSetting do
  @behaviour Access

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field(:health, :boolean, default: true)
    field(:geo, :boolean, default: true)
    field(:local_shell, :boolean, default: true)
    field(:logging, :boolean, default: true)
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
