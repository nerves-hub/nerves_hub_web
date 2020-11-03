defmodule NervesHubWebCore.Products.Product do
  use Ecto.Schema
  import Ecto.Changeset

  alias NervesHubWebCore.Devices.Device
  alias NervesHubWebCore.Accounts.Org
  alias NervesHubWebCore.Firmwares.Firmware
  alias NervesHubWebCore.Products.ProductUser

  @required_params [:name, :org_id]
  @optional_params [:delta_updatable]

  schema "products" do
    has_many(:devices, Device)
    has_many(:firmwares, Firmware)
    has_many(:product_users, ProductUser)
    has_many(:users, through: [:product_users, :user])

    belongs_to(:org, Org)

    field(:name, :string)
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
    product
    |> cast(params, @required_params ++ @optional_params)
    |> no_assoc_constraint(:devices, message: "Product has associated devices")
    |> no_assoc_constraint(:firmwares, message: "Product has associated firmwares")
  end
end
