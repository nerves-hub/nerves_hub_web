defmodule NervesHub.Fwup do
  @moduledoc """
  Helpers for dealing with files created by FWUP.
  """

  @required_metadata_keys [:architecture, :platform, :product, :uuid, :version]
  @optional_metadata_keys [:author, :description, :misc, :vcs_identifier]

  @metadata_regex Regex.compile!("meta-(?<key>[^\n]+)=\"(?<value>[^\n]+)\"")

  @doc """
  Decode and parse metadata from a FWUP file.
  """
  @spec metadata(String.t()) ::
          {:ok, map()}
          | {:error, :invalid_fwup_file}
          | {:error, :invalid_metadata}
  def metadata(file_path) do
    with {:ok, metadata} <- get_metadata(file_path),
         parsed_metadata <- parse_metadata(metadata),
         {:ok, required_metadata} <- required_values(parsed_metadata),
         optional_metadata <- optional_values(parsed_metadata),
         complete <- Map.merge(required_metadata, optional_metadata) do
      {:ok, complete}
    end
  end

  defp get_metadata(filepath) do
    case System.cmd("fwup", ["-m", "-i", filepath]) do
      {metadata, 0} ->
        {:ok, metadata}

      {_error, _} ->
        {:error, :invalid_fwup_file}
    end
  end

  defp parse_metadata(metadata) do
    Regex.scan(@metadata_regex, metadata)
    |> Enum.reduce(%{}, fn line, acc ->
      [_, key, value] = line

      key =
        key
        |> String.replace("-", "_")
        |> String.to_atom()

      Map.put(acc, key, value)
    end)
  end

  defp required_values(metadata) do
    slice = Map.take(metadata, @required_metadata_keys)
    slice_keys = Map.keys(slice)

    if Enum.sort(slice_keys) == @required_metadata_keys do
      {:ok, slice}
    else
      {:error, :invalid_metadata}
    end
  end

  defp optional_values(metadata) do
    defaults = Map.new(@optional_metadata_keys, fn x -> {x, nil} end)

    slice = Map.take(metadata, @optional_metadata_keys)

    Map.merge(defaults, slice)
  end
end
