defmodule NervesHub.Fwup do
  @moduledoc """
  Helpers for dealing with files created by FWUP.
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
  end

  @doc """
  Decode and parse metadata from a FWUP file.
  """
  @spec metadata(String.t()) ::
          {:ok, struct()}
          | {:error, :invalid_fwup_file | :invalid_metadata}
  def metadata(file_path) do
    with {:ok, metadata} <- get_metadata(file_path),
         parsed_metadata <- parse_metadata(metadata),
         {:ok, metadata_struct} <- transform_to_struct(parsed_metadata) do
      {:ok, metadata_struct}
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
    keys = Map.keys(Map.from_struct(Metadata))
    filtered = Map.take(metadata, keys)
    {:ok, struct!(Metadata, filtered)}
  rescue
    _ -> {:error, :invalid_metadata}
  end
end
