defmodule NervesHubCore.Firmwares.Firmware do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

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
    :vcs_identifier
  ]
  @required_params [
    :architecture,
    :platform,
    :product_id,
    :uuid,
    :upload_metadata,
    :version
  ]

  schema "firmwares" do
    belongs_to(:product, Product)
    belongs_to(:org_key, OrgKey)
    has_many(:deployments, Deployment)

    field(:architecture, :string)
    field(:author, :string)
    field(:description, :string)
    field(:misc, :string)
    field(:platform, :string)
    field(:upload_metadata, :map)
    field(:uuid, :string)
    field(:vcs_identifier, :string)
    field(:version, :string)

    timestamps()
  end

  def changeset(%Firmware{} = firmware, params) do
    firmware
    |> cast(params, @required_params ++ @optional_params)
    |> validate_required(@required_params)
    |> validate_firmware_limit()
    |> unique_constraint(:uuid, name: :firmwares_product_id_uuid_index)
    |> foreign_key_constraint(:deployments, name: :deployments_firmware_id_fkey)
  end

  defp validate_firmware_limit(%Ecto.Changeset{changes: %{product_id: product_id}} = cs) do
    if too_many_firmwares?(product_id) do
      cs |> add_error(:product, "firmware limit reached")
    else
      cs
    end
  end

  defp validate_firmware_limit(%Ecto.Changeset{} = cs) do
    cs
  end

  defp too_many_firmwares?(product_id) do
    firmware_count =
      from(f in Firmware, where: f.product_id == ^product_id, select: count(f.id))
      |> Repo.one()

    product_firmware_limit = Application.get_env(:nerves_hub_core, :product_firmware_limit)
    firmware_count + 1 > product_firmware_limit
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
