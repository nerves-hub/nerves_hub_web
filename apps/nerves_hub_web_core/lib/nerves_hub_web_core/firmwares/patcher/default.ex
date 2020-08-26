defmodule NervesHubWebCore.Firmwares.Patcher.Default do
  @moduledoc """
  Default NervesHubWebCore.Firmwares.Patcher implementation
  """

  @behaviour NervesHubWebCore.Firmwares.Patcher

  @impl NervesHubWebCore.Firmwares.Patcher
  def create_patch_file(source_url, target_url) do
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
    output = Path.join(work_dir, output_filename) |> Path.expand()

    source_work_dir = Path.join(work_dir, "source")
    target_work_dir = Path.join(work_dir, "target")
    output_work_dir = Path.join(work_dir, "output")

    File.mkdir_p(source_work_dir)
    File.mkdir_p(target_work_dir)
    File.mkdir_p(Path.join(output_work_dir, "data"))

    {_, 0} = System.cmd("unzip", ["-qq", source_path, "-d", source_work_dir])
    {_, 0} = System.cmd("unzip", ["-qq", target_path, "-d", target_work_dir])

    source_rootfs = Path.join([source_work_dir, "data", "rootfs.img"])
    target_rootfs = Path.join([target_work_dir, "data", "rootfs.img"])
    out_rootfs = Path.join([output_work_dir, "data", "rootfs.img"])

    {_, 0} =
      System.cmd("xdelta3", ["-A", "-S", "-f", "-s", source_rootfs, target_rootfs, out_rootfs])

    File.mkdir_p!(Path.dirname(output))
    File.cp!(target_path, output)

    {_, 0} = System.cmd("zip", ["-qq", output, "data/rootfs.img"], cd: output_work_dir)
    output
  end

  @impl NervesHubWebCore.Firmwares.Patcher
  def cleanup_patch_files(patch_path) do
    patch_path
    |> Path.dirname()
    |> File.rm_rf!()

    :ok
  end
end
