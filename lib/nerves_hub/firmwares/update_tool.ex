defmodule NervesHub.Firmwares.UpdateTool do
  @moduledoc """
  A behaviour module for the tool that handles firmware updates.

  ## Choosing a tool

  A NervesHub instance can carry more than one tool at a time — an org shipping
  fwup images to Nerves devices and ESP-IDF images to ESP32s uses both. Which
  one runs is decided in two different ways depending on the direction:

    * **On upload**, nothing has been recorded yet, so the file itself decides.
      `for_file/1` asks each configured tool whether it recognises the bytes
      (`c:recognises?/1`), which is a magic-number check rather than a guess
      from the filename.

    * **On read**, the `tool` column recorded at upload time decides —
      `for_firmware/1`. A firmware is always handled by the tool that ingested
      it, so adding or removing tools from the configuration never changes how
      existing firmware is interpreted.

  Configure the set of tools with:

      config :nerves_hub, :update_tools, %{
        "fwup" => NervesHub.Firmwares.UpdateTool.Fwup,
        "esp-idf" => NervesHub.Firmwares.UpdateTool.EspIdf
      }

  The older single-tool keys (`:update_tool`, and before it `:delta_updater`)
  still work and pin the instance to exactly that one tool.
  """

  alias NervesHub.Accounts.OrgKey
  alias NervesHub.Devices.Device
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Firmwares.FirmwareDelta

  defmodule Metadata do
    @enforce_keys [:architecture, :platform, :product, :uuid, :version]

    defstruct [
      :architecture,
      :author,
      :description,
      :misc,
      :platform,
      :product,
      :uuid,
      :vcs_identifier,
      :version
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

  @typedoc "Metadata about the file upload."
  @type upload_metadata :: map()
  @typedoc """
  Firmware archive metadata.

  The `firmware_metadata` field has enforced fields that are expected.
  The `tool_metadata` field is a free-form map to capture information the tool needs.

  A tool may add its own keys beyond these — `Fwup` carries the extracted
  `meta.conf` path so that `c:delta_updatable?/1` can read it without a second
  extraction. Only the tool that produced the map ever reads those keys.
  """
  @type metadata :: %{
          :firmware_metadata => Metadata.t(),
          :tool_metadata => map(),
          :tool => String.t(),
          :tool_delta_required_version => String.t(),
          :tool_full_required_version => String.t(),
          optional(atom()) => term()
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
  The name recorded in `firmwares.tool`, and the key this tool is configured under.
  """
  @callback tool_name() :: String.t()

  @doc """
  The extension used when storing an archive this tool produced, leading dot included.
  """
  @callback file_extension() :: String.t()

  @doc """
  Whether this tool can handle the given file.

  Called against every configured tool when a firmware is uploaded, so it should
  read as little as possible — a magic number, not a full parse — and must never
  raise on arbitrary bytes.
  """
  @callback recognises?(String.t()) :: boolean()

  @doc """
  Verify that an uploaded archive was signed by one of the org's keys.

  Each image format carries its signature differently, so this cannot live
  outside the tool: fwup verifies an Ed25519 signature over the archive, while
  ESP-IDF appends a Secure Boot v2 signature block.

  `{:ok, nil}` means the archive is legitimately unsigned and the tool accepts
  it — the firmware is then recorded with no `org_key_id`.
  """
  @callback verify_signature(String.t(), [OrgKey.t()]) ::
              {:ok, OrgKey.t() | nil} | {:error, term()}

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
              {target_id :: String.t(), target_url :: String.t()},
              work_dir :: String.t()
            ) ::
              {:ok, delta_file_metadata()} | {:error, term()}

  @doc """
  Called to cleanup any files or directories create during the firmware delta creation process.

  The return value of this function is not checked.
  """
  @callback cleanup_firmware_delta_files(String.t()) :: :ok

  @doc """
  Whether this format can be delta updated at all.

  Distinct from `c:delta_updatable?/1`, which answers for one archive: this
  answers for the format. A tool returning false never has deltas generated for
  it, however a deployment group is configured — generating a patch nothing can
  apply costs worker time and object storage and reports success in the UI.
  """
  @callback supports_deltas?() :: boolean()

  @doc """
  Checks whether delta updating is enabled for the firmware the metadata describes.

  Takes the map returned by `c:get_firmware_metadata_from_file/1` so that a tool
  can reuse whatever it already extracted rather than re-reading the archive.
  """
  @callback delta_updatable?(metadata()) :: boolean()

  @doc """
  Check if a device is ready for a delta firmware update or requires a complete
  update.
  """
  @callback device_update_type(device :: Device.t(), Firmware.t()) :: :delta | :full

  @doc """
  Whether this tool recognises the firmware metadata a device reported on join.

  Devices predate the tool registry and mostly cannot be upgraded in the field,
  so a device is not required to say which format it speaks. A tool identifies
  its own metadata by the keys present — `nerves_fw_uuid` for fwup, for example.

  A device that *can* say so should send `"update_tool"` in its join params,
  which takes precedence over this.
  """
  @callback recognises_device_metadata?(params :: map()) :: boolean()

  @doc """
  Translate the firmware metadata a device reported into NervesHub's shape.

  Returns a plain map for `NervesHub.Firmwares.FirmwareMetadata.changeset/2`.
  Values that cannot be derived should be `nil` rather than omitted — a device
  reporting partial metadata falls back to a database lookup by UUID.
  """
  @callback metadata_from_device(params :: map()) :: map()

  @doc """
  Every tool this instance is configured to use, keyed by `tool_name/0`.
  """
  @spec all() :: %{String.t() => module()}
  def all() do
    case Application.get_env(:nerves_hub, :update_tools) do
      nil -> legacy_tool() || default_tools()
      tools -> tools
    end
  end

  @doc """
  Every tool this build knows about, whether or not it is enabled for upload.

  `all/0` governs what an instance will *accept*; this governs what it can
  *read*. Firmware already in the database has to stay interpretable after a
  format is turned off again, or disabling the flag would orphan it rather than
  simply stopping new uploads.
  """
  @spec known() :: %{String.t() => module()}
  def known(), do: %{"fwup" => __MODULE__.Fwup, "esp-idf" => __MODULE__.EspIdf}

  # fwup is always available. Anything else is off unless the platform turns it
  # on: enabling a format is a decision about what an instance will accept and
  # sign, not something a deploy should acquire by upgrading.
  defp default_tools() do
    if esp_idf_enabled?() do
      known()
    else
      %{"fwup" => __MODULE__.Fwup}
    end
  end

  @doc """
  Whether this instance accepts ESP-IDF application images.

  Set by `ESP_IDF_FIRMWARE_ENABLED` at runtime. Off by default — ESP-IDF images
  cannot currently be signature-verified (see
  `NervesHub.Firmwares.UpdateTool.EspIdf`), so accepting them is a deliberate
  choice about an instance's trust model.
  """
  @spec esp_idf_enabled?() :: boolean()
  def esp_idf_enabled?() do
    Application.get_env(:nerves_hub, :esp_idf_firmware_enabled, false)
  end

  # The pre-registry configuration pinned the whole instance to one tool. Honour
  # it so that an existing deployment does not silently start accepting formats
  # it never accepted before.
  defp legacy_tool() do
    configured =
      Application.get_env(:nerves_hub, :update_tool) ||
        Application.get_env(:nerves_hub, :delta_updater)

    case configured do
      nil -> nil
      module -> %{module.tool_name() => module}
    end
  end

  @doc """
  The tool that handles an already-recorded firmware or delta.
  """
  @spec for_firmware(Firmware.t() | FirmwareDelta.t()) ::
          {:ok, module()} | {:error, {:unknown_update_tool, String.t()}}
  def for_firmware(%Firmware{tool: tool}), do: fetch(tool)
  def for_firmware(%FirmwareDelta{tool: tool}), do: fetch(tool)

  @doc """
  The tool that recognises an uploaded file, by inspecting the file itself.
  """
  @spec for_file(String.t()) :: {:ok, module()} | {:error, :unrecognised_firmware_format}
  def for_file(filepath) do
    all()
    |> Map.values()
    |> Enum.find(& &1.recognises?(filepath))
    |> case do
      nil -> {:error, :unrecognised_firmware_format}
      module -> {:ok, module}
    end
  end

  @doc """
  The tool that handles the firmware metadata a device reported.

  Prefers an explicit `"update_tool"` in the params, then asks each tool whether
  it recognises the keys, and finally falls back to `fallback` — which exists so
  that a device reporting nothing recognisable is still read the way it was
  before this seam existed, rather than losing its metadata.
  """
  @spec for_device_metadata(map(), module()) :: module()
  def for_device_metadata(params, fallback \\ __MODULE__.Fwup) do
    declared = params["update_tool"]

    with true <- is_binary(declared),
         {:ok, module} <- fetch(declared) do
      module
    else
      _ -> sniff_device_metadata(params, fallback)
    end
  end

  defp sniff_device_metadata(params, fallback) do
    # `known/0`, not `all/0`: a device running firmware uploaded before the
    # format was disabled still has to have its metadata read.
    known()
    |> Map.values()
    |> Enum.find(& &1.recognises_device_metadata?(params))
    |> Kernel.||(fallback)
  end

  @spec fetch(String.t() | nil) :: {:ok, module()} | {:error, {:unknown_update_tool, String.t()}}
  defp fetch(tool) do
    case Map.fetch(known(), tool) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, {:unknown_update_tool, tool}}
    end
  end
end
