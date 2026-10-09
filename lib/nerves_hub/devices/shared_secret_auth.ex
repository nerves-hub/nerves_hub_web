defmodule NervesHub.Devices.SharedSecretAuth do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Accounts.User
  alias NervesHub.Devices.Device
  alias NervesHub.Products

  @type t :: %__MODULE__{}

  @key_prefix "nhd"

  schema "device_shared_secret_auths" do
    belongs_to(:device, Device)
    belongs_to(:product_shared_secret_auth, Products.SharedSecretAuth)
    belongs_to(:created_by, User)
    belongs_to(:deactivated_by, User)

    field(:key, :string)
    field(:secret, :string)

    field(:deactivated_at, :utc_datetime)
    field(:last_used, :utc_datetime)

    timestamps()
  end

  def create_changeset(%Device{id: device_id}, attrs \\ %{}) do
    cast(%__MODULE__{device_id: device_id}, attrs, [:product_shared_secret_auth_id])
    |> put_change(:key, "#{@key_prefix}_#{generate_key()}")
    |> put_change(:secret, generate_secret())
    |> validate_required([:device_id, :key, :secret])
    |> validate_format(:key, ~r/^#{@key_prefix}_[a-zA-Z0-9\-_]{43}$/)
    |> validate_format(:secret, ~r/^[a-zA-Z0-9\-\/\+]{43}$/)
    |> foreign_key_constraint(:device_id)
    |> foreign_key_constraint(:product_shared_secret_auth_id)
    |> unique_constraint(:key)
    |> unique_constraint(:secret)
  end

  def deactivate_changeset(%__MODULE__{} = auth) do
    change(auth, %{deactivated_at: DateTime.truncate(DateTime.utc_now(), :second)})
  end

  # The key is URL-safe, so the API can address it in a path. Keys made before
  # this had "/" and "+" and still authenticate, since the format is only
  # checked here.
  defp generate_key() do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  # The secret keeps the standard alphabet. It never leaves the device, and a
  # value that isn't URL-safe is harder to put in a URL by accident.
  defp generate_secret() do
    :crypto.strong_rand_bytes(32) |> Base.encode64(padding: false)
  end
end
