defmodule NervesHub.Products.Product do
  use Ecto.Schema
  import Ecto.Changeset

  alias NervesHub.Accounts.Org
  alias NervesHub.Archives.Archive
  alias NervesHub.Devices.CACertificate
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.UpdateStat
  alias NervesHub.Extensions.ProductExtensionsSetting
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.Products.SharedSecretAuth
  alias NervesHub.Scripts.Script

  @required_params [:name, :org_id]

  @type t :: %__MODULE__{}

  @derive {Phoenix.Param, key: :name}
  schema "products" do
    has_many(:devices, Device, where: [deleted_at: nil])
    has_many(:firmwares, Firmware)
    has_many(:jitp, CACertificate.JITP)
    has_many(:archives, Archive)
    has_many(:scripts, Script)
    has_many(:deployment_groups, DeploymentGroup)
    has_many(:update_stats, UpdateStat, on_delete: :nilify_all)

    has_many(:shared_secret_auths, SharedSecretAuth, preload_order: [desc: :deactivated_at, asc: :id])

    belongs_to(:org, Org, where: [deleted_at: nil])

    field(:name, :string)
    field(:deleted_at, :utc_datetime)
    embeds_one(:extensions, ProductExtensionsSetting, on_replace: :update)

    field(:device_count, :integer, virtual: true)

    timestamps()
  end

  def change_user_role(struct, params) do
    cast(struct, params, ~w(role)a)
    |> validate_required(~w(role)a)
  end

  @doc false
  def changeset(product, params) do
    product
    |> cast(params, @required_params)
    |> cast_embed(:extensions)
    |> update_change(:name, &trim/1)
    |> validate_required(@required_params)
    |> unique_constraint(:name, name: :products_org_id_name_index)
  end

  def delete_changeset(product, _params \\ %{}) do
    deleted_at = DateTime.truncate(DateTime.utc_now(), :second)

    product
    |> change()
    |> put_change(:deleted_at, deleted_at)
  end

  defp trim(string) when is_binary(string) do
    string
    |> String.split(" ", trim: true)
    |> Enum.join(" ")
  end

  defp trim(string), do: string
end
