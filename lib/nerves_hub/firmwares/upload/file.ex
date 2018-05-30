defmodule NervesHub.Firmware.Upload.File do
  def upload_file(filepath, filename, tenant_id) do
    config = Application.get_env(:nerves_hub, NervesHub.Firmware.Upload.File)
    random_string = :crypto.strong_rand_bytes(12) |> Base.url_encode64()
    path = Path.join([Integer.to_string(tenant_id), random_string])
    local_path = Path.join([config[:local_path], path])

    with :ok <- File.mkdir_p(local_path),
         :ok <- File.cp(filepath, Path.join([local_path, filename])) do
      url = Application.get_env(:nerves_hub, NervesHubWeb.Endpoint)[:url]
      port = if Enum.member?([443, 80], url[:port]), do: "", else: ":#{url[:port]}"

      public_path =
        "#{url[:scheme]}://#{url[:host]}#{port}/" <>
          (Path.join([config[:public_path], path, filename])
           |> String.trim("/"))

      {:ok, %{public_path: public_path}}
    end
  end

  def download_file(firmware) do
    firmware.upload_metadata["public_path"]
  end
end
