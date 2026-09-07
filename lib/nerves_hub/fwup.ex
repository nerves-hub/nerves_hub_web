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
    with {:ok, metadata} <- get_metadata(file_path) do
      parsed_metadata = parse_metadata(metadata)
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

  # Every `meta-*` key in the file used to be atomised here, and only then did
  # `transform_to_struct/1` throw the unrecognised ones away. Atoms are never
  # reclaimed, so a firmware carrying arbitrary metadata keys left the node
  # permanently heavier -- and enough of them would exhaust the atom table.
  # Match against the names we actually keep instead, and mint nothing.
  defp parse_metadata(metadata) do
    known = Map.new(Metadata.keys(), &{Atom.to_string(&1), &1})

    Regex.scan(~r/meta-(?<key>[^\n]+)=\"?(?<value>[^\"\n]+)/, metadata)
    |> Enum.reduce(%{}, fn [_, key, value], acc ->
      case Map.fetch(known, String.replace(key, "-", "_")) do
        {:ok, key} -> Map.put(acc, key, value)
        :error -> acc
      end
    end)
  end

  defp transform_to_struct(metadata) do
    filtered = Map.take(metadata, Metadata.keys())
    {:ok, struct!(Metadata, filtered)}
  rescue
    _ -> {:error, :invalid_metadata}
  end
end
