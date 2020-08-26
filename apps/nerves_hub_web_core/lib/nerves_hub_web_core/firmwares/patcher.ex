defmodule NervesHubWebCore.Firmwares.Patcher do
  @moduledoc """
  A behaviour module for creating firmware patch files.
  """

  @typedoc "Metadata about the file upload."
  @type upload_metadata :: map()

  @doc """
  Called to create a firmware patch file on the local filesystem
  """
  @callback create_patch_file(String.t(), String.t()) :: String.t()

  @doc """
  Called to cleanup any files or directories create during the patch creation process.

  The return value of this function is not checked.
  """
  @callback cleanup_patch_files(String.t()) :: :ok
end
