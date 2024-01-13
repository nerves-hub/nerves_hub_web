defmodule NervesHub.Devices.SharedSecretAuth do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Devices.Device
  alias NervesHub.Products

  @type t :: %__MODULE__{}

  @key_prefix "nhd"

  schema "device_shared_secret_auths" do
    belongs_to(:device, Device)
    belongs_to(:product_shared_secret_auth, Products.SharedSecretAuth)

    field(:key, :string)
    field(:secret, :string)

    field(:deactivated_at, :utc_datetime)

    timestamps()
  end

  def create_changeset(%Device{id: device_id}, attrs \\ %{}) do
    cast(%__MODULE__{device_id: device_id}, attrs, [:product_shared_secret_auth_id])
    |> put_change(:key, "#{@key_prefix}_#{generate_token()}")
    |> put_change(:secret, generate_token())
    |> validate_required([:device_id, :key, :secret])
    |> validate_format(:key, ~r/^#{@key_prefix}_[a-zA-Z0-9\-\/\+]{43}$/)
    |> validate_format(:secret, ~r/^[a-zA-Z0-9\-\/\+]{43}$/)
    |> foreign_key_constraint(:device_id)
    |> foreign_key_constraint(:product_shared_secret_auth_id)
    |> unique_constraint(:key)
    |> unique_constraint(:secret)
  end

  def deactivate_changeset(%__MODULE__{} = auth) do
    change(auth, %{deactivated_at: DateTime.truncate(DateTime.utc_now(), :second)})
  end

  defp generate_token() do
    :crypto.strong_rand_bytes(32) |> Base.encode64(padding: false)
  end
end
