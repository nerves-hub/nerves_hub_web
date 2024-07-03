defmodule NervesHub.Support.Archives do
  defmodule MetaParams do
    defstruct product: "nerves-hub",
              description: "Manifest",
              version: "1.0.0",
              platform: "generic",
              architecture: "generic",
              author: "me"
  end

  def create_signed_archive(dir, key_name, archive_name, output_name, meta_params \\ %{}) do
    create_archive(dir, archive_name, meta_params)
    sign_archive(dir, key_name, archive_name, output_name)
  end

  @doc """
  Create an unsigned archive image, and return the path to that image.
  """
  def create_archive(dir, archive_name, meta_params \\ %{}) do
    conf_path = make_conf(struct(MetaParams, meta_params))
    out_path = Path.join([dir, archive_name <> ".fw"])
    File.rm(out_path)

    System.cmd("fwup", [
      "-c",
      "-f",
      conf_path,
      "-o",
      out_path
    ])

    {:ok, out_path}
  end

  @doc """
  Sign a archive image, and return the path to that image. The `archive_name`
  argument must match the name of a archive created with `create_archive/2`.
  """
  def sign_archive(dir, key_name, archive_name, output_name) do
    output_path = Path.join([dir, output_name <> ".fw"])

    System.cmd(
      "fwup",
      [
        "-S",
        "-s",
        Path.join([dir, key_name <> ".priv"]),
        "-i",
        Path.join([dir, archive_name <> ".fw"]),
        "-o",
        output_path
      ],
      stderr_to_stdout: true
    )

    {:ok, output_path}
  end

  def make_conf(metadata) do
    path = Path.join([System.tmp_dir(), "#{Ecto.UUID.generate()}.conf"])
    File.write!(path, build_conf(metadata))
    path
  end

  def build_conf(metadata) do
    """
    meta-product = "#{metadata.product}"
    meta-description = "#{metadata.description}"
    meta-version = "#{metadata.version}"
    meta-platform = "#{metadata.platform}"
    meta-architecture = "#{metadata.architecture}"

    file-resource manifest.json {
      contents = "Hello"
    }
    """
  end
end
