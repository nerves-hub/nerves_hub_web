defmodule Beamware.Firmwares.Firmware do
  use Ecto.Schema

  import Ecto.Changeset

  alias Beamware.Accounts.Tenant
  alias Beamware.Deployments.Deployment
  alias __MODULE__

  @type t :: %__MODULE__{}

  schema "firmwares" do
    belongs_to(:tenant, Tenant)
    has_many(:deployment, Deployment)

    field(:filename, :string)
    field(:product, :string)
    field(:platform, :string)
    field(:architecture, :string)
    field(:timestamp, :utc_datetime)
    field(:signed, :boolean)
    field(:tenant_key_id, :integer)
    field(:metadata, :string)
    field(:upload_metadata, :map)

    timestamps()
  end

  def changeset(%Firmware{} = firmware, params) do
    fields = [
      :tenant_id,
      :filename,
      :product,
      :platform,
      :architecture,
      :timestamp,
      :signed,
      :tenant_key_id,
      :metadata,
      :upload_metadata
    ]

    firmware
    |> cast(params, fields)
    |> validate_required(fields -- [:tenant_key_id])
  end

  @spec version(Firmware.t()) :: {:ok, String.t()} | {:error, :not_found}
  def version(%Firmware{} = firmware) do
    metadata_item(firmware, "meta-version")
  end

  @spec metadata_item(Firmware.t(), String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def metadata_item(%Firmware{metadata: metadata}, key) when is_binary(key) do
    {:ok, regex} = "#{key}=\"(?<item>[^\n]+)\"" |> Regex.compile()

    regex
    |> Regex.named_captures(metadata)
    |> case do
      %{"item" => item} ->
        {:ok, item}

      _ ->
        {:error, :not_found}
    end
  end
end
