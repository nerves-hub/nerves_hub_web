defmodule NervesHubWebCore.Firmwares.Upload.File do
  @moduledoc """
  Local file adapter for CRUDing firmware files.
  """

  @behaviour NervesHubWebCore.Firmwares.Upload

  @type upload_metadata :: %{local_path: String.t(), public_path: String.t()}

  @impl NervesHubWebCore.Firmwares.Upload
  def upload_file(source, %{local_path: local_path}) do
    with :ok <- local_path |> Path.dirname() |> File.mkdir_p(),
         :ok <- File.cp(source, local_path) do
      :ok
    end
  end

  @impl NervesHubWebCore.Firmwares.Upload
  def download_file(%{upload_metadata: metadata}), do: do_download_file(metadata)
  defp do_download_file(%{public_path: path}), do: {:ok, path}
  defp do_download_file(%{"public_path" => path}), do: {:ok, path}

  @impl NervesHubWebCore.Firmwares.Upload
  def delete_file(%{local_path: path}), do: delete_file(path)
  def delete_file(%{"local_path" => path}), do: delete_file(path)

  def delete_file(path) when is_binary(path) do
    # Sometimes fw files may be stored in temporary places that
    # get cleared on reboots, especially when using this locally.
    # So if the file doesn't exist, don't attempt to remove
    if File.exists?(path), do: File.rm!(path), else: :ok
  end

  @impl NervesHubWebCore.Firmwares.Upload
  def metadata(org_id, filename) do
    config = Application.get_env(:nerves_hub_www, __MODULE__)
    common_path = "#{org_id}"
    local_path = Path.join([config[:local_path], common_path, filename])
    url = Application.get_env(:nerves_hub_www, NervesHubWWWWeb.Endpoint)[:url]
    port = if Enum.member?([443, 80], url[:port]), do: "", else: ":#{url[:port]}"

    public_path =
      "#{url[:scheme]}://#{url[:host]}#{port}/" <>
        (Path.join([config[:public_path], common_path, filename])
         |> String.trim("/"))

    %{
      public_path: public_path,
      local_path: local_path
    }
  end
end
