defmodule NervesHub.Firmwares.Firmware do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Accounts.Tenant
  alias NervesHub.Deployments.Deployment
  alias __MODULE__

  @type t :: %__MODULE__{}

  schema "firmwares" do
    belongs_to(:tenant, Tenant)
    has_many(:deployment, Deployment)

    field(:version, :string)
    field(:product, :string)
    field(:platform, :string)
    field(:architecture, :string)
    field(:timestamp, :utc_datetime)
    field(:tenant_key_id, :integer)
    field(:metadata, :string)
    field(:upload_metadata, :map)

    timestamps()
  end

  def changeset(%Firmware{} = firmware, params) do
    fields = [
      :tenant_id,
      :version,
      :product,
      :platform,
      :architecture,
      :timestamp,
      :tenant_key_id,
      :metadata,
      :upload_metadata
    ]

    firmware
    |> cast(params, fields)
    |> validate_required(fields)
  end

  def version(%Firmware{} = firmware) do
    metadata_item(firmware.metadata, "meta-version")
  end

  @spec timestamp(String.t()) ::
          {:ok, DateTime.t()}
          | {:error, atom}
  def timestamp(metadata) do
    metadata_item(metadata, "meta-creation-date")
    |> case do
      {:ok, t} -> DateTime.from_iso8601(t)
      error -> error
    end
    |> case do
      {:ok, datetime, _} -> {:ok, datetime}
      error -> error
    end
  end

  @spec metadata_item(String.t(), String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def metadata_item(metadata, key) when is_binary(key) do
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
