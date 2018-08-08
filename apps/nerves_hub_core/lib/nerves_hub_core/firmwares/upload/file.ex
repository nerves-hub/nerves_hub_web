defmodule NervesHubCore.Firmwares.Upload.File do
  @spec upload_file(String.t(), String.t(), integer()) ::
          {:ok, map}
          | {:error, atom()}
  def upload_file(filepath, filename, org_id) do
    config = Application.get_env(:nerves_hub_www, __MODULE__)
    random_string = :crypto.strong_rand_bytes(12) |> Base.url_encode64()
    path = Path.join([Integer.to_string(org_id), random_string])
    local_path = Path.join([config[:local_path], path])

    with :ok <- File.mkdir_p(local_path),
         :ok <- File.cp(filepath, Path.join([local_path, filename])) do
      url = Application.get_env(:nerves_hub_www, NervesHubWWWWeb.Endpoint)[:url]
      port = if Enum.member?([443, 80], url[:port]), do: "", else: ":#{url[:port]}"

      public_path =
        "#{url[:scheme]}://#{url[:host]}#{port}/" <>
          (Path.join([config[:public_path], path, filename])
           |> String.trim("/"))

      {:ok, %{public_path: public_path}}
    end
  end

  @spec download_file(Firmware.t()) ::
          {:ok, String.t()}
          | {:error, String.t()}
  def download_file(firmware) do
    {:ok, firmware.upload_metadata["public_path"]}
  end
end
