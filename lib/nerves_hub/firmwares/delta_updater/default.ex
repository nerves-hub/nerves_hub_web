defmodule NervesHub.Firmwares.DeltaUpdater.Default do
  @moduledoc """
  Default NervesHub.Firmwares.DeltaUpdater implementation
  """

  @behaviour NervesHub.Firmwares.DeltaUpdater

  @impl NervesHub.Firmwares.DeltaUpdater
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

  @impl NervesHub.Firmwares.DeltaUpdater
  def cleanup_firmware_delta_files(firmware_delta_path) do
    _ =
      firmware_delta_path
      |> Path.dirname()
      |> File.rm_rf!()

    :ok
  end

  @impl NervesHub.Firmwares.DeltaUpdater
  def delta_updatable?(file_path) do
    {meta, 0} = System.cmd("unzip", ["-qqp", file_path, "meta.conf"])

    (meta =~ "delta-source-raw-offset" && meta =~ "delta-source-raw-count") or
      (meta =~ "delta-source-fat-offset" && meta =~ "delta-source-fat-path")
  end

  def do_delta_file(source_path, target_path, output_path, work_dir) do
    _ = File.mkdir_p(work_dir)

    source_work_dir = Path.join(work_dir, "source")
    target_work_dir = Path.join(work_dir, "target")
    output_work_dir = Path.join(work_dir, "output")

    _ = File.mkdir_p(source_work_dir)
    _ = File.mkdir_p(target_work_dir)
    _ = File.mkdir_p(output_work_dir)

    {_, 0} = System.cmd("unzip", ["-qq", source_path, "-d", source_work_dir])
    {_, 0} = System.cmd("unzip", ["-qq", target_path, "-d", target_work_dir])

    _ =
      for absolute <- Path.wildcard(target_work_dir <> "/**"), not File.dir?(absolute) do
        path = Path.relative_to(absolute, target_work_dir)

        _ =
          if String.starts_with?(path, "meta.") do
            File.cp!(Path.join(target_work_dir, path), Path.join(output_work_dir, path))
          else
            output_path = Path.join(output_work_dir, path)

            output_path
            |> Path.dirname()
            |> File.mkdir_p!()

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

                {_, 0} = System.cmd("xdelta3", args, stderr_to_stdout: true)

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

    output_path
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
        {_, 0} = System.cmd("zip", args, cd: workdir)

        :ok
    end
  end
end
