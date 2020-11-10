defmodule NervesHubWebCore.Firmwares.DeltaUpdater do
  @moduledoc """
  A behaviour module for creating firmware delta files.
  """

  @typedoc "Metadata about the file upload."
  @type upload_metadata :: map()

  @doc """
  Called to create a firmware delta file on the local filesystem
  """
  @callback create_firmware_delta_file(String.t(), String.t()) :: String.t()

  @doc """
  Called to cleanup any files or directories create during the firmware delta creation process.

  The return value of this function is not checked.
  """
  @callback cleanup_firmware_delta_files(String.t()) :: :ok

  @doc """
  Checks a firmware file's meta.conf to see if delta updating is enabled
  """
  @callback delta_updatable?(String.t()) :: boolean()
end
