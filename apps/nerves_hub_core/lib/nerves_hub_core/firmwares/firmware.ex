defmodule NervesHubCore.Firmwares.Firmware do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias NervesHubCore.Accounts
  alias NervesHubCore.Accounts.OrgKey
  alias NervesHubCore.Deployments.Deployment
  alias NervesHubCore.Products.Product
  alias NervesHubCore.Repo

  alias __MODULE__

  @type t :: %__MODULE__{}
  @optional_params [
    :author,
    :description,
    :misc,
    :org_key_id,
    :ttl_until,
    :vcs_identifier
  ]
  @required_params [
    :architecture,
    :platform,
    :product_id,
    :ttl,
    :uuid,
    :upload_metadata,
    :version
  ]
  @virtual_params [
    :org_id,
    :size
  ]

  schema "firmwares" do
    belongs_to(:product, Product)
    belongs_to(:org_key, OrgKey)
    has_many(:deployments, Deployment)

    field(:architecture, :string)
    field(:author, :string)
    field(:description, :string)
    field(:size, :integer, virtual: true)
    field(:misc, :string)
    field(:org_id, :integer, virtual: true)
    field(:platform, :string)
    field(:ttl, :integer)
    field(:ttl_until, :utc_datetime)
    field(:upload_metadata, :map)
    field(:uuid, :string)
    field(:vcs_identifier, :string)
    field(:version, :string)

    timestamps()
  end

  def create_changeset(%Firmware{} = firmware, params) do
    firmware
    |> cast(params, @required_params ++ @virtual_params ++ @optional_params)
    |> validate_required(@required_params ++ @virtual_params)
    |> validate_limits()
    |> unique_constraint(:uuid, name: :firmwares_product_id_uuid_index)
    |> foreign_key_constraint(:deployments, name: :deployments_firmware_id_fkey)
  end

  def update_changeset(%Firmware{} = firmware, params) do
    firmware
    |> cast(params, @required_params ++ @optional_params)
    |> validate_required(@required_params)
    |> validate_limits()
    |> unique_constraint(:uuid, name: :firmwares_product_id_uuid_index)
    |> foreign_key_constraint(:deployments, name: :deployments_firmware_id_fkey)
  end

  def delete_changeset(%Firmware{} = firmware, params) do
    firmware
    |> cast(params, @required_params ++ @optional_params)
    |> foreign_key_constraint(:deployments, name: :deployments_firmware_id_fkey)
  end

  defp validate_limits(%Ecto.Changeset{changes: %{org_id: org_id}} = cs) do
    limits = Accounts.get_org_limit_by_org_id(org_id)

    cs
    |> validate_firmware_size(limits)
    |> validate_firmware_limit(limits)
    |> validate_firmware_ttl(limits)
  end

  defp validate_limits(cs), do: cs

  defp validate_firmware_size(%Ecto.Changeset{changes: %{size: firmware_size}} = cs, %{
         firmware_size: firmware_size_limit
       }) do
    if firmware_size > firmware_size_limit do
      add_error(cs, :firmware, "firmware exceeds maximum size",
        size: firmware_size,
        limit: firmware_size_limit
      )
    else
      cs
    end
  end

  defp validate_firmware_size(%Ecto.Changeset{} = cs, _limits) do
    cs
  end

  defp validate_firmware_limit(%Ecto.Changeset{changes: %{product_id: product_id}} = cs, limits) do
    if too_many_firmwares?(product_id, limits) do
      add_error(cs, :product, "firmware limit reached")
    else
      cs
    end
  end

  defp validate_firmware_limit(%Ecto.Changeset{} = cs, _limits) do
    cs
  end

  defp validate_firmware_ttl(%Ecto.Changeset{changes: %{ttl: ttl}} = cs, %{
         firmware_ttl_seconds: limit
       }) do
    if ttl > limit do
      add_error(cs, :firmware, "cannot set ttl #{ttl} > #{limit}")
    else
      cs
    end
  end

  defp validate_firmware_ttl(cs, _limits), do: cs

  defp too_many_firmwares?(product_id, %{firmware_per_product: limit}) do
    firmware_count =
      from(f in Firmware,
        where: f.product_id == ^product_id,
        select: count(f.id)
      )
      |> Repo.one()

    firmware_count + 1 > limit
  end

  def with_product(firmware_query) do
    firmware_query
    |> preload(:product)
  end

  @spec fetch_metadata_item(String.t(), String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def fetch_metadata_item(metadata, key) when is_binary(key) do
    {:ok, regex} = "#{key}=\"(?<item>[^\n]+)\"" |> Regex.compile()

    case Regex.named_captures(regex, metadata) do
      %{"item" => item} -> {:ok, item}
      _ -> {:error, :not_found}
    end
  end

  @spec get_metadata_item(String.t(), String.t(), any()) :: String.t() | nil
  def get_metadata_item(metadata, key, default \\ nil) when is_binary(key) do
    case fetch_metadata_item(metadata, key) do
      {:ok, metadata_item} -> metadata_item
      {:error, :not_found} -> default
    end
  end
end
