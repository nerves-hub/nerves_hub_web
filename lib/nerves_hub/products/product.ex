defmodule NervesHub.Products.Product do
  use Ecto.Schema
  import Ecto.Changeset

  alias NervesHub.Devices.Device
  alias NervesHub.Accounts.Org
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Products.ProductUser
  alias NervesHub.Devices.CACertificate
  alias NervesHub.Repo

  @required_params [:name, :org_id]
  @optional_params [:delta_updatable]

  @type t :: %__MODULE__{}

  schema "products" do
    has_many(:devices, Device, where: [deleted_at: nil])
    has_many(:firmwares, Firmware)
    has_many(:product_users, ProductUser)
    has_many(:users, through: [:product_users, :user])
    has_many(:jitp, CACertificate.JITP)

    belongs_to(:org, Org, where: [deleted_at: nil])

    field(:name, :string)
    field(:deleted_at, :utc_datetime)
    field(:delta_updatable, :boolean, default: false)

    timestamps()
  end

  def add_user(struct, params) do
    cast(struct, params, [:role])
    |> validate_required([:role])
    |> unique_constraint(
      :product_users,
      name: "product_users_index",
      message: "is already member"
    )
  end

  def change_user_role(struct, params) do
    cast(struct, params, ~w(role)a)
    |> validate_required(~w(role)a)
  end

  @doc false
  def changeset(product, params) do
    product
    |> cast(params, @required_params ++ @optional_params)
    |> validate_required(@required_params)
    |> unique_constraint(:name, name: :products_org_id_name_index)
  end

  def delete_changeset(product, params \\ %{}) do
    deleted_at = DateTime.truncate(DateTime.utc_now(), :second)

    product
    |> cast(params, @required_params ++ @optional_params)
    |> no_soft_deleted_assoc(:devices, message: "Product has associated devices")
    |> no_soft_deleted_assoc(:firmwares, message: "Product has associated firmwares")
    |> put_change(:deleted_at, deleted_at)
  end

  defp no_soft_deleted_assoc(%{data: data} = changeset, assoc, opts) do
    default_message = "is still associated with this entry"
    message = Keyword.get(opts, :message, default_message)

    empty? =
      data
      |> Repo.preload(assoc)
      |> Map.get(assoc, [])
      |> Enum.filter(&is_nil(Map.get(&1, :deleted_at)))
      |> Enum.empty?()

    if empty? do
      changeset
    else
      add_error(changeset, assoc, message)
    end
  end
end
