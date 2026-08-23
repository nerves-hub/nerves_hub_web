defmodule NervesHub.Support.AtomVM do
  @moduledoc """
  Builds synthetic AtomVM packbeam archives for tests.

  The real thing comes out of `rebar3 atomvm packbeam` and contains compiled
  BEAM modules, but everything NervesHub reads is the 24 byte magic, the entry
  headers, and one `<app>/priv/application.bin` holding a serialised
  `{application, Name, Props}`. A test archive is those, with entry payloads
  that are filler, and it exercises exactly the same parsing path as a real
  build.

  The application term is encoded by hand rather than with
  `:erlang.term_to_binary/1`, because doing it the easy way would create an atom
  for the application name on the test node — and one of the things worth
  testing is that reading an archive never does that.

  This mirrors `NervesHub.Support.EspIdf` in intent: it lets a test produce an
  uploadable firmware file without a toolchain.
  """

  # A shebang, NUL padded to a 4 byte boundary. `avmpack_is_valid` compares
  # exactly these bytes.
  @magic <<"#!/usr/bin/env AtomVM\n", 0, 0>>

  # packbeam's own flags: BEAM_CODE_FLAG and the flag for a plain data file.
  @beam_code_flag 0x02
  @data_flag 0x04

  @doc """
  Build a packbeam as a binary.

  ## Options

    * `:product` — the OTP application name, which NervesHub files firmware
      under, so it must match a product to upload
    * `:version` — the application's `vsn`, defaults to `"1.0.0"`
    * `:description` — the application's `description`
    * `:modules` — names of `.beam` entries to include ahead of the metadata
    * `:properties` — extra `{key, value}` application properties
    * `:applications` — further `{name, version}` pairs, each contributing its
      own `application.bin` after the first, as a dependency's would
  """
  @spec packbeam(keyword()) :: binary()
  def packbeam(opts \\ []) do
    product = Keyword.get(opts, :product, "nerves_hub")
    version = Keyword.get(opts, :version, "1.0.0")
    description = Keyword.get(opts, :description, "a test application")
    modules = Keyword.get(opts, :modules, ["nerves_hub_link"])
    properties = Keyword.get(opts, :properties, [])
    dependencies = Keyword.get(opts, :applications, [])

    beams = Enum.map(modules, &entry("#{&1}.beam", @beam_code_flag, filler(&1)))

    specs =
      [{product, version, description} | Enum.map(dependencies, fn {n, v} -> {n, v, "a dependency"} end)]
      |> Enum.map(fn {name, vsn, desc} ->
        entry("#{name}/priv/application.bin", @data_flag, application_bin(name, vsn, desc, properties))
      end)

    IO.iodata_to_binary([@magic, beams, specs, terminator()])
  end

  @doc """
  Write a packbeam to disk, ready to hand to `NervesHub.Firmwares.create_firmware/3`.

  Takes the same options as `packbeam/1`, plus `:dir` and `:name`.
  """
  @spec create_firmware(String.t(), keyword()) :: {:ok, Path.t()}
  def create_firmware(product_name, opts \\ []) do
    dir = Keyword.get(opts, :dir, System.tmp_dir!())
    name = Keyword.get(opts, :name, "atomvm-#{System.unique_integer([:positive])}")
    path = Path.join(dir, "#{name}.avm")

    archive = opts |> Keyword.put(:product, product_name) |> packbeam()

    archive =
      case Keyword.get(opts, :sign_with) do
        nil -> archive
        seed -> sign(archive, seed)
      end

    File.write!(path, archive)

    {:ok, path}
  end

  @doc """
  An Ed25519 keypair in the shape NervesHub stores and `nh-avm` signs with.

  The public half is base64, which is how fwup writes a `.pub` file and how an
  organization key is stored. The private half is the raw 32 byte seed.
  """
  @spec keypair() :: {binary(), binary()}
  def keypair() do
    {public, seed} = :crypto.generate_key(:eddsa, :ed25519)
    {Base.encode64(public), seed}
  end

  @doc """
  Sign an archive, appending the signature as the last entry.

  Mirrors `nh_signature:sign/2` in nerves_hub_link_atomvm_esp32. The signed
  range is every byte before the signature entry begins, so signing is a pure
  append and nothing before it moves.
  """
  @spec sign(binary(), binary()) :: binary()
  def sign(archive, seed) do
    prefix = binary_part(archive, 0, byte_size(archive) - byte_size(terminator()))
    signature = :crypto.sign(:eddsa, :none, prefix, [seed, :ed25519])

    prefix <> entry("nerves_hub/signature", @data_flag, <<"NH1", 1::8, signature::binary>>) <> terminator()
  end

  @doc "The 24 byte header every packbeam starts with."
  @spec magic() :: <<_::192>>
  def magic(), do: @magic

  @doc """
  Build one packbeam entry.

  A 12 byte header — size, flags, reserved — then a NUL terminated name padded
  to a 4 byte boundary, then the data, itself padded so the entry as a whole
  keeps the next one aligned. `size` covers all of it.
  """
  @spec entry(String.t(), non_neg_integer(), binary()) :: binary()
  def entry(name, flags, data) do
    name_field = pad4(name <> <<0>>)
    size = 12 + byte_size(name_field) + byte_size(pad4(data))

    <<size::32, flags::32, 0::32>> <> name_field <> pad4(data)
  end

  @doc "The zeroed header that ends an archive."
  @spec terminator() :: <<_::96>>
  def terminator(), do: <<0::32, 0::32, 0::32>>

  # A 4 byte length, then the term. `packbeam_api` writes the length and then
  # ignores it on the way back in; NervesHub honours it.
  defp application_bin(name, version, description, properties) do
    term =
      tuple([
        atom("application"),
        atom(name),
        list([
          tuple([atom("description"), charlist(description)]),
          tuple([atom("vsn"), charlist(version)]),
          tuple([atom("registered"), nil_ext()]),
          tuple([atom("applications"), list([atom("kernel"), atom("stdlib")])])
          | Enum.map(properties, fn {k, v} -> tuple([atom(to_string(k)), charlist(to_string(v))]) end)
        ])
      ])

    encoded = <<131>> <> term
    <<byte_size(encoded)::32>> <> encoded
  end

  # The external term format tags an application spec actually uses.
  defp atom(name) when byte_size(name) < 256, do: <<119, byte_size(name)::8>> <> name
  defp charlist(string), do: <<107, byte_size(string)::16>> <> string
  defp nil_ext(), do: <<106>>
  defp tuple(elements), do: IO.iodata_to_binary([<<104, length(elements)::8>>, elements])
  defp list(elements), do: IO.iodata_to_binary([<<108, length(elements)::32>>, elements, nil_ext()])

  defp filler(seed), do: :binary.copy(<<0xAA>>, 16 + byte_size(to_string(seed)))

  defp pad4(binary) do
    case rem(byte_size(binary), 4) do
      0 -> binary
      remainder -> binary <> :binary.copy(<<0>>, 4 - remainder)
    end
  end
end
