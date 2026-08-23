defmodule NervesHub.Support.RaucBundle do
  @moduledoc """
  Builds RAUC bundles for tests, with openssl rather than `rauc`.

  A verity bundle is a payload, a CMS signature holding the manifest, and an
  eight-byte length — all three of which openssl and `dd` can produce. Building
  them here rather than checking in a fixture means a test can vary the manifest,
  sign with the wrong key, or truncate the footer, which is most of what is worth
  testing about a format parser.

  The payload is not a real SquashFS. Nothing in
  `NervesHub.Firmwares.UpdateTool.Rauc` reads past its magic number, because for
  a verity bundle everything it needs is in the signature — so a real filesystem
  here would test `mksquashfs`, not NervesHub.
  """

  @squashfs_magic "hsqs"

  @doc """
  A certificate and private key, in PEM, for signing bundles.

  Self-signed: the certificate is both the signer and the trust anchor, which is
  what an organization registering a single key in NervesHub has.
  """
  def keypair(common_name \\ "test-signer") do
    dir = tmp_dir()
    key_path = Path.join(dir, "key.pem")
    cert_path = Path.join(dir, "cert.pem")

    {_, 0} =
      System.cmd(
        "openssl",
        [
          "req",
          "-x509",
          "-newkey",
          "rsa:2048",
          "-keyout",
          key_path,
          "-out",
          cert_path,
          "-days",
          "1",
          "-nodes",
          "-subj",
          "/CN=#{common_name}"
        ],
        stderr_to_stdout: true,
        # Nothing here needs the caller's environment, and inheriting it means
        # openssl reads whatever OPENSSL_* the shell happened to carry.
        env: []
      )

    %{
      certificate: File.read!(cert_path),
      certificate_path: cert_path,
      key_path: key_path,
      dir: dir
    }
  end

  @doc """
  A manifest with the sections NervesHub reads.

  Pass `update:` or `meta:` to override or remove fields — `nil` drops a key, so
  a test can build a manifest that is missing exactly one thing.
  """
  def manifest(opts \\ []) do
    update =
      Keyword.merge(
        [compatible: "acme-gateway", version: "1.4.2", description: "a test bundle"],
        Keyword.get(opts, :update, [])
      )

    meta =
      Keyword.merge(
        [product: "Gateway", architecture: "aarch64"],
        Keyword.get(opts, :meta, [])
      )

    """
    [update]
    #{render(update)}
    [bundle]
    format=verity

    [meta.nerveshub]
    #{render(meta)}
    """
  end

  defp render(pairs) do
    pairs
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Enum.map_join("\n", fn {key, value} -> "#{key}=#{value}" end)
    |> Kernel.<>("\n")
  end

  @doc """
  Write a verity-format bundle signed by `signer`.

  `detached: true` produces the plain format instead — a signature over the
  payload with no manifest inside it — which is what the tool refuses.
  """
  def write(path, signer, opts \\ []) do
    manifest = Keyword.get(opts, :manifest, manifest())
    detached? = Keyword.get(opts, :detached, false)

    # 4 KiB aligned, as RAUC expects a payload to be.
    payload = @squashfs_magic <> :binary.copy(<<0>>, 4096 - byte_size(@squashfs_magic))

    dir = tmp_dir()
    content_path = Path.join(dir, "content")
    cms_path = Path.join(dir, "cms.der")

    File.write!(content_path, if(detached?, do: payload, else: manifest))

    args =
      [
        "cms",
        "-sign",
        "-binary",
        "-in",
        content_path,
        "-signer",
        signer.certificate_path,
        "-inkey",
        signer.key_path,
        "-outform",
        "DER",
        "-out",
        cms_path
      ] ++ if detached?, do: [], else: ["-nodetach"]

    {_, 0} = System.cmd("openssl", args, stderr_to_stdout: true, env: [])

    signature = File.read!(cms_path)
    footer = <<byte_size(signature)::unsigned-big-integer-size(64)>>

    File.write!(path, payload <> signature <> footer)

    path
  end

  defp tmp_dir() do
    dir = Path.join(System.tmp_dir!(), "rauc-fixture-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf(dir) end)
    dir
  end
end
