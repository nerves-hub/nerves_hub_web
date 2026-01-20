defmodule NervesHub.Firmwares.Upload do
  @moduledoc """
  A behaviour module for managing firmware files within a file storage system.
  """

  alias NervesHub.Accounts.Org
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Firmwares.FirmwareDelta

  @typedoc "Metadata about the file upload."
  @type upload_metadata :: map()

  @doc """
  Called to upload a file to where it needs to live.
  """
  @callback upload_file(String.t(), upload_metadata()) ::
              :ok
              | {:error, atom()}

  @doc """
  Called to retrieve a user accessible URL for the file.
  """
  @callback download_file(Firmware.t() | FirmwareDelta.t()) ::
              {:ok, String.t()}
              | {:error, String.t()}

  @doc """
  Called to remove files from the storage location.
  """
  @callback delete_file(Firmware.t()) :: :ok | {:error, any()}

  @doc """
  Called to generate the upload_metadata that will be persisted for later lookup.
  """
  @callback metadata(Org.id(), String.t()) :: upload_metadata()

  @doc """
  Called to generate the upload_metadata specific to delta firmwares that will be persisted for later lookup.
  """
  @callback delta_metadata(
              Org.id(),
              source_firmware_uuid :: String.t(),
              target_firmware_uuid :: String.t()
            ) :: upload_metadata()
end
