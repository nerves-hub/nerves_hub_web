defmodule NervesHubWebCore.Firmwares.Upload.File do
  @moduledoc """
  Local file adapter for CRUDing firmware files.
  """

  @type upload_metadata :: %{local_path: String.t(), public_path: String.t()}

  @spec upload_file(String.t(), upload_metadata()) ::
          :ok
          | {:error, atom()}
  def upload_file(source, %{local_path: local_path}) do
    with :ok <- local_path |> Path.dirname() |> File.mkdir_p(),
         :ok <- File.cp(source, local_path) do
      :ok
    end
  end

  @spec download_file(Firmware.t()) ::
          {:ok, String.t()}
          | {:error, String.t()}
  def download_file(firmware) do
    {:ok, firmware.upload_metadata["public_path"]}
  end

  @spec delete_file(Firmware.t()) :: :ok
  def delete_file(%{upload_metadata: %{local_path: path}}) do
    # Sometimes fw files may be stored in temporary places that
    # get cleared on reboots, especially when using this locally.
    # So if the file doesn't exist, don't attempt to remove
    if File.exists?(path), do: File.rm!(path), else: :ok
  end

  def delete_file(%{upload_metadata: %{"local_path" => path}}) do
    delete_file(%{upload_metadata: %{local_path: path}})
  end

  @spec metadata(Org.id(), String.t()) :: upload_metadata()
  def metadata(org_id, filename) do
    config = Application.get_env(:nerves_hub_web_core, __MODULE__)
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
