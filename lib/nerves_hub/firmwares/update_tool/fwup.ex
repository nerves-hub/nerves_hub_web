defmodule NervesHub.Firmwares.UpdateTool.Fwup do
  @moduledoc """
  Default NervesHub.Firmwares.UpdateTool implementation, providing fwup support.
  """

  @behaviour NervesHub.Firmwares.UpdateTool

  alias NervesHub.Firmwares
  alias NervesHub.Fwup, as: FwupUtil

  @impl NervesHub.Firmwares.UpdateTool
  def get_firmware_metadata_from_file(filepath) do
    with {:ok, firmware_metadata} <- FwupUtil.metadata(filepath),
         {:ok, meta_conf_path} <- extract_meta_conf_locally(filepath),
         {:ok, tool_metadata} <- Confuse.Fwup.get_feature_usage(meta_conf_path) do
      %{firmware_metadata: firmware_metadata, tool_metadata: tool_metadata}
    else
      err ->
        err
    end
  end

  @impl NervesHub.Firmwares.UpdateTool
  def create_firmware_delta_file(source_url, target_url) do
    uuid = Ecto.UUID.generate()
    work_dir = Path.join(System.tmp_dir(), uuid) |> Path.expand()
    _ = File.mkdir_p(work_dir)

    source_path = Path.join(work_dir, "source.fw") |> Path.expand()
    target_path = Path.join(work_dir, "target.fw") |> Path.expand()

    {:ok, :saved_to_file} =
      :httpc.request(
        :get,
        {source_url |> to_charlist, []},
        [],
        stream: source_path |> to_charlist
      )

    {:ok, :saved_to_file} =
      :httpc.request(
        :get,
        {target_url |> to_charlist, []},
        [],
        stream: target_path |> to_charlist
      )

    output_filename = uuid <> ".fw"
    output_path = Path.join(work_dir, output_filename) |> Path.expand()

    do_delta_file(source_path, target_path, output_path, work_dir)
  end

  @impl NervesHub.Firmwares.UpdateTool
  def cleanup_firmware_delta_files(firmware_delta_path) do
    _ =
      firmware_delta_path
      |> Path.dirname()
      |> File.rm_rf!()

    :ok
  end

  @impl NervesHub.Firmwares.UpdateTool
  def delta_updatable?(file_path) do
    {meta, 0} = System.cmd("unzip", ["-qqp", file_path, "meta.conf"], env: [])

    path =
      System.tmp_dir!()
      |> Path.join("meta.conf")

    File.write!(path, meta)
    {:ok, feature_usage} = Confuse.Fwup.get_feature_usage(path)

    feature_usage.raw_deltas? or feature_usage.fat_deltas?
  end

  @very_safe_version Version.parse!("1.13.0")
  @oldest_version Version.parse!("0.2.0")
  @impl NervesHub.Firmwares.UpdateTool
  def device_update_type(device, deployment_group) do
    # Unknown version, assume oldest
    device_fwup_version = device.firmware_metadata.fwup_version || @oldest_version
    source = Firmwares.get_firmware_by_uuid(device.firmware_metadata.uuid)
    target = deployment_group.firmware

    delta_result = Firmwares.get_firmware_delta_by_source_and_target(source.id, target.id)

    with {:ok, %{tool_metadata: tm}} <- delta_result,
         delta_min <- tm["delta_fwup_version"] || @very_safe_version,
         {:ok, delta_version} <- Version.parse(delta_min),
         :lt <- Version.compare(delta_version, device_fwup_version) do
      :delta
    else
      _ ->
        :full
    end
  rescue
    _ ->
      :full
  end

  def do_delta_file(source_path, target_path, output_path, work_dir) do
    _ = File.mkdir_p(work_dir)

    source_work_dir = Path.join(work_dir, "source")
    target_work_dir = Path.join(work_dir, "target")
    output_work_dir = Path.join(work_dir, "output")

    _ = File.mkdir_p(source_work_dir)
    _ = File.mkdir_p(target_work_dir)
    _ = File.mkdir_p(output_work_dir)

    %{size: source_size} = File.stat!(source_path)
    %{size: target_size} = File.stat!(target_path)

    {_, 0} = System.cmd("unzip", ["-qq", source_path, "-d", source_work_dir], env: [])
    {_, 0} = System.cmd("unzip", ["-qq", target_path, "-d", target_work_dir], env: [])

    {:ok, deltas} = Confuse.Fwup.get_delta_files(Path.join(target_work_dir, "meta.conf"))

    all_delta_files =
      Enum.flat_map(deltas, fn {_k, files} ->
        files
      end)
      |> Enum.uniq()

    if all_delta_files == [] do
      {:error, :no_delta_support_in_firmware}
    else
      _ =
        for absolute <- Path.wildcard(target_work_dir <> "/**"), not File.dir?(absolute) do
          path = Path.relative_to(absolute, target_work_dir)

          output_path = Path.join(output_work_dir, path)

          output_path
          |> Path.dirname()
          |> File.mkdir_p!()

          _ =
            if String.starts_with?(path, "meta.") or path not in all_delta_files do
              File.cp!(Path.join(target_work_dir, path), Path.join(output_work_dir, path))
            else
              source_filepath = Path.join(source_work_dir, path)
              target_filepath = Path.join(target_work_dir, path)

              case File.stat(source_filepath) do
                {:ok, _} ->
                  args = [
                    "-A",
                    "-S",
                    "-f",
                    "-s",
                    source_filepath,
                    target_filepath,
                    output_path
                  ]

                  {_, 0} = System.cmd("xdelta3", args, stderr_to_stdout: true, env: [])

                {:error, :enoent} ->
                  File.cp!(target_filepath, output_path)
              end
            end
        end

      # firmware archive files order matters:
      # 1. meta.conf.ed25519 (optional)
      # 2. meta.conf
      # 3. other...
      [
        "meta.conf.*",
        "meta.conf",
        "data"
      ]
      |> Enum.each(&add_to_zip(&1, output_work_dir, output_path))

      {:ok, %{size: size}} = File.stat(output_path)

      {:ok,
       %{
         filepath: output_path,
         size: size,
         source_size: source_size,
         target_size: target_size,
         tool: "fwup",
         tool_metadata: %{}
       }}
    end
  end

  defp add_to_zip(glob, workdir, output) do
    workdir
    |> Path.join(glob)
    |> Path.wildcard()
    |> case do
      [] ->
        :ok

      paths ->
        args = ["-r", "-qq", output | Enum.map(paths, &Path.relative_to(&1, workdir))]
        {_, 0} = System.cmd("zip", args, cd: workdir, env: [])

        :ok
    end
  end

  defp extract_meta_conf_locally(filepath) do
    try do
      path =
        File.mkdir_p!(
          Path.join(System.tmp_dir!(), "nerves-hub-meta-#{System.unique_integer(:positive)}")
        )

      stream = File.stream!(path)

      filepath
      |> Unzip.LocalFile.open()
      |> Unzip.file_stream!("meta.conf")
      |> Enum.into(stream, &IO.iodata_to_binary/1)

      {:ok, path}
    rescue
      _ ->
        {:error, :unzip_failed}
    end
  end
end
