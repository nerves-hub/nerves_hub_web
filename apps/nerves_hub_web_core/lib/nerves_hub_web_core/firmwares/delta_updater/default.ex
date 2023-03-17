defmodule NervesHubWebCore.Firmwares.DeltaUpdater.Default do
  @moduledoc """
  Default NervesHubWebCore.Firmwares.DeltaUpdater implementation
  """

  @behaviour NervesHubWebCore.Firmwares.DeltaUpdater

  @impl NervesHubWebCore.Firmwares.DeltaUpdater
  def create_firmware_delta_file(source_url, target_url) do
    uuid = Ecto.UUID.generate()
    work_dir = Path.join(System.tmp_dir(), uuid) |> Path.expand()
    File.mkdir_p(work_dir)

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

  @impl NervesHubWebCore.Firmwares.DeltaUpdater
  def cleanup_firmware_delta_files(firmware_delta_path) do
    firmware_delta_path
    |> Path.dirname()
    |> File.rm_rf!()

    :ok
  end

  @impl NervesHubWebCore.Firmwares.DeltaUpdater
  def delta_updatable?(file_path) do
    {meta, 0} = System.cmd("unzip", ["-qqp", file_path, "meta.conf"])

    (meta =~ "delta-source-raw-offset" && meta =~ "delta-source-raw-count") or
      (meta =~ "delta-source-fat-offset" && meta =~ "delta-source-fat-path")
  end

  def do_delta_file(source_path, target_path, output_path, work_dir) do
    File.mkdir_p(work_dir)

    source_work_dir = Path.join(work_dir, "source")
    target_work_dir = Path.join(work_dir, "target")
    output_work_dir = Path.join(work_dir, "output")

    File.mkdir_p(source_work_dir)
    File.mkdir_p(target_work_dir)
    File.mkdir_p(output_work_dir)

    {_, 0} = System.cmd("unzip", ["-qq", source_path, "-d", source_work_dir])
    {_, 0} = System.cmd("unzip", ["-qq", target_path, "-d", target_work_dir])

    for path <- Path.wildcard(target_work_dir <> "/**") do
      path = Regex.replace(~r/^#{target_work_dir}\//, path, "")

      unless File.dir?(Path.join(target_work_dir, path)) do
        :ok = handle_content(path, source_work_dir, target_work_dir, output_work_dir)
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

  defp handle_content("meta." <> _ = path, _source_dir, target_dir, out_dir) do
    do_copy(Path.join(target_dir, path), Path.join(out_dir, path))
  end

  defp handle_content(path, source_dir, target_dir, out_dir) do
    do_delta(Path.join(source_dir, path), Path.join(target_dir, path), Path.join(out_dir, path))
  end

  defp do_copy(source, target) do
    target |> Path.dirname() |> File.mkdir_p!()
    File.cp(source, target)
  end

  defp do_delta(source, target, out) do
    out |> Path.dirname() |> File.mkdir_p!()

    with {_, 0} <-
           System.cmd("xdelta3", ["-A", "-S", "-f", "-s", source, target, out]) do
      :ok
    else
      {_, code} ->
        {:error, code}
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
        {_, 0} =
          System.cmd(
            "zip",
            ["-r", "-qq", output | Enum.map(paths, &Path.relative_to(&1, workdir))],
            cd: workdir
          )

        :ok
    end
  end
end
