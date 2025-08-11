defmodule NervesHub.Fwup do
  @moduledoc """
  Helpers for dealing with files created by FWUP.
  """

  alias NervesHub.Firmwares.UpdateTool.Metadata

  @doc """
  Decode and parse metadata from a FWUP file.
  """
  @spec metadata(String.t()) ::
          {:ok, Metadata.t()}
          | {:error, :invalid_fwup_file | :invalid_metadata}
  def metadata(file_path) do
    with {:ok, metadata} <- get_metadata(file_path),
         parsed_metadata <- parse_metadata(metadata) do
      transform_to_struct(parsed_metadata)
    end
  end

  defp get_metadata(filepath) do
    case System.cmd("fwup", ["-m", "-i", filepath], env: []) do
      {metadata, 0} ->
        {:ok, metadata}

      {_error, _} ->
        {:error, :invalid_fwup_file}
    end
  end

  defp parse_metadata(metadata) do
    Regex.scan(~r/meta-(?<key>[^\n]+)=\"(?<value>[^\n]+)\"/, metadata)
    |> Enum.reduce(%{}, fn line, acc ->
      [_, key, value] = line

      key =
        key
        |> String.replace("-", "_")
        |> String.to_atom()

      Map.put(acc, key, value)
    end)
  end

  defp transform_to_struct(metadata) do
    filtered = Map.take(metadata, Metadata.keys())
    {:ok, struct!(Metadata, filtered)}
  rescue
    _ -> {:error, :invalid_metadata}
  end
end
