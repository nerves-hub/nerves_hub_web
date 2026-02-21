defmodule NervesHub.Firmwares.FirmwareDelta do
  use Ecto.Schema

  import Ecto.Changeset

  alias __MODULE__
  alias NervesHub.Firmwares.Firmware

  @type t :: %__MODULE__{}

  schema "firmware_deltas" do
    belongs_to(:source, Firmware)
    belongs_to(:target, Firmware)

    field(:status, Ecto.Enum, values: [:processing, :completed, :failed, :timed_out])
    field(:tool, :string)
    # Metadata about the delta that the update tool needs to operate
    field(:tool_metadata, :map)
    field(:size, :integer, default: 0)
    field(:source_size, :integer, default: 0)
    field(:target_size, :integer, default: 0)
    field(:upload_metadata, :map)

    timestamps()
  end

  @spec start_changeset(firmware_delta :: FirmwareDelta.t(), source_id :: integer(), target_id :: integer()) ::
          Ecto.Changeset.t()
  def start_changeset(firmware_delta \\ %FirmwareDelta{}, source_id, target_id) do
    params = %{
      status: :processing,
      source_id: source_id,
      target_id: target_id,
      tool: "pending",
      tool_metadata: %{},
      upload_metadata: %{}
    }

    firmware_delta
    |> cast(params, [:status, :source_id, :target_id, :tool, :tool_metadata, :upload_metadata])
    |> validate_required([
      :status,
      :source_id,
      :target_id,
      :tool,
      :tool_metadata,
      :upload_metadata
    ])
    |> unique_constraint(:unique_firmware_delta, name: :source_id_target_id_unique_index)
    |> foreign_key_constraint(:source_id, name: :firmware_deltas_source_id_fkey)
    |> foreign_key_constraint(:target_id, name: :firmware_deltas_target_id_fkey)
  end

  @spec complete_changeset(
          firmware_delta :: FirmwareDelta.t(),
          tool :: String.t(),
          size :: non_neg_integer(),
          source_size :: non_neg_integer(),
          target_size :: non_neg_integer(),
          tool_metadata :: map(),
          upload_metadata :: map()
        ) :: Ecto.Changeset.t()
  def complete_changeset(
        %FirmwareDelta{} = firmware_delta,
        tool,
        size,
        source_size,
        target_size,
        tool_metadata,
        upload_metadata
      ) do
    firmware_delta
    |> cast(
      %{
        status: :completed,
        tool: tool,
        size: size,
        source_size: source_size,
        target_size: target_size,
        tool_metadata: tool_metadata,
        upload_metadata: upload_metadata
      },
      [
        :status,
        :tool,
        :size,
        :source_size,
        :target_size,
        :tool_metadata,
        :upload_metadata
      ]
    )
    |> validate_required([
      :status,
      :tool,
      :size,
      :source_size,
      :target_size,
      :tool_metadata,
      :upload_metadata
    ])
    |> unique_constraint(:unique_firmware_delta, name: :source_id_target_id_unique_index)
    |> foreign_key_constraint(:source_id, name: :firmware_deltas_source_id_fkey)
    |> foreign_key_constraint(:target_id, name: :firmware_deltas_target_id_fkey)
  end

  @spec fail_changeset(FirmwareDelta.t()) :: Ecto.Changeset.t()
  def fail_changeset(%FirmwareDelta{} = firmware_delta) do
    firmware_delta
    |> cast(%{status: :failed}, [:status])
    |> validate_required([:status])
  end

  @spec time_out_changeset(FirmwareDelta.t()) :: Ecto.Changeset.t()
  def time_out_changeset(%FirmwareDelta{} = firmware_delta) do
    firmware_delta
    |> cast(%{status: :timed_out}, [:status])
    |> validate_required([:status])
  end

  @spec create_changeset(FirmwareDelta.t(), map()) :: Ecto.Changeset.t()
  def create_changeset(%FirmwareDelta{} = firmware_delta, params) do
    firmware_delta
    |> cast(params, [
      :source_id,
      :target_id,
      :status,
      :upload_metadata,
      :tool,
      :tool_metadata,
      :size,
      :source_size,
      :target_size
    ])
    |> validate_required([
      :source_id,
      :target_id,
      :status,
      :upload_metadata,
      :tool,
      :tool_metadata,
      :size,
      :source_size,
      :target_size
    ])
    |> unique_constraint(:unique_firmware_delta, name: :source_id_target_id_unique_index)
    |> foreign_key_constraint(:source_id, name: :firmware_deltas_source_id_fkey)
    |> foreign_key_constraint(:target_id, name: :firmware_deltas_target_id_fkey)
  end
end
