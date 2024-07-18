defmodule NervesHub.Fwup do
  def metadata(file_path) do
    with {:ok, metadata} <- get_metadata(file_path),
         {:ok, uuid} <- metadata_value(metadata, "meta-uuid"),
         {:ok, architecture} <- metadata_value(metadata, "meta-architecture"),
         {:ok, platform} <- metadata_value(metadata, "meta-platform"),
         {:ok, product} <- metadata_value(metadata, "meta-product"),
         {:ok, version} <- metadata_value(metadata, "meta-version"),
         {:ok, author} <- metadata_value(metadata, "meta-author", nil),
         {:ok, description} <- metadata_value(metadata, "meta-description", nil),
         {:ok, misc} <- metadata_value(metadata, "meta-misc", nil),
         {:ok, vcs_identifier} <- metadata_value(metadata, "meta-vcs-identifier", nil) do
      metadata = %{
        architecture: architecture,
        author: author,
        description: description,
        misc: misc,
        platform: platform,
        product: product,
        uuid: uuid,
        vcs_identifier: vcs_identifier,
        version: version
      }

      {:ok, metadata}
    end
  end

  defp get_metadata(filepath) do
    case System.cmd("fwup", ["-m", "-i", filepath]) do
      {metadata, 0} ->
        {:ok, metadata}

      {error, _} ->
        {:error, error}
    end
  end

  defp metadata_value(metadata, key) when is_binary(key) do
    {:ok, regex} = "#{key}=\"(?<value>[^\n]+)\"" |> Regex.compile()

    case Regex.named_captures(regex, metadata) do
      %{"value" => value} ->
        {:ok, value}

      _ ->
        {:error, {key, :not_found}}
    end
  end

  defp metadata_value(metadata, key, default) when is_binary(key) do
    case metadata_value(metadata, key) do
      {:ok, metadata_item} ->
        {:ok, metadata_item}

      {:error, {_, :not_found}} ->
        {:ok, default}
    end
  end
end
