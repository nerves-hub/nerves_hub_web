defmodule NervesHub.Firmwares.UpdateTool do
  @moduledoc """
  A behaviour module for the tool that handles firmware updates.
  """

  defmodule Metadata do
    @enforce_keys [:architecture, :platform, :product, :uuid, :version]

    defstruct [
      :architecture,
      :platform,
      :product,
      :uuid,
      :version,
      :author,
      :description,
      :misc,
      :vcs_identifier
    ]

    @type t() :: %__MODULE__{
            architecture: String.t(),
            platform: String.t(),
            product: String.t(),
            uuid: String.t(),
            version: String.t(),
            author: String.t(),
            description: String.t(),
            misc: String.t(),
            vcs_identifier: String.t()
          }

    def keys() do
      blank_values =
        Enum.reduce(@enforce_keys, %{}, fn key, acc ->
          Map.put(acc, key, nil)
        end)

      struct!(Metadata, blank_values)
      |> Map.from_struct()
      |> Map.keys()
    end
  end

  alias NervesHub.Devices.Device
  alias NervesHub.Firmwares.Firmware

  @typedoc "Metadata about the file upload."
  @type upload_metadata :: map()
  @typedoc """
  Firmware archive metadata.

  The `firmware_metadata` field has enforced fields that are expected.
  The `tool_metadata` field is a free-form map to capture information the tool needs.
  """
  @type metadata :: %{
          firmware_metadata: Metadata.t(),
          tool_metadata: map(),
          tool: String.t(),
          tool_delta_required_version: String.t(),
          tool_full_required_version: String.t()
        }
  @typedoc """
  On delta creation we get a file, we get some size information and we get any
  tool metadata that we should store about the delta archive. Maybe minimum
  required tool version for example.
  """
  @type delta_file_metadata :: %{
          filepath: String.t(),
          size: non_neg_integer(),
          source_size: non_neg_integer(),
          target_size: non_neg_integer(),
          tool: String.t(),
          tool_metadata: map()
        }

  @doc """
  Retrieves metadata from a firmware file.
  """
  @callback get_firmware_metadata_from_file(String.t()) ::
              {:ok, metadata()} | {:error, term()}

  @doc """
  Retrieves metadata from a firmware upload.
  """
  @callback get_firmware_metadata_from_upload(Firmware.t()) ::
              {:ok, metadata()} | {:error, term()}

  @doc """
  Called to create a firmware delta file on the local filesystem
  """
  @callback create_firmware_delta_file(
              {source_id :: String.t(), source_url :: String.t()},
              {target_id :: String.t(), target_url :: String.t()}
            ) ::
              {:ok, delta_file_metadata()} | {:error, term()}

  @doc """
  Called to cleanup any files or directories create during the firmware delta creation process.

  The return value of this function is not checked.
  """
  @callback cleanup_firmware_delta_files(String.t()) :: :ok

  @doc """
  Checks a firmware file's meta.conf to see if delta updating is enabled
  """
  @callback delta_updatable?(String.t()) :: boolean()

  @doc """
  Check if a device is ready for a delta firmware update or requires a complete
  update.
  """
  @callback device_update_type(device :: Device.t(), Firmware.t()) :: :delta | :full
end
