defmodule NervesHub.Firmwares.DeltaUpdateTest do
  use ExUnit.Case, async: true

  alias NervesHub.Firmwares.DeltaUpdater.Default

  @raw File.read!("test/fixtures/fwup/raw.conf")
  @fat File.read!("test/fixtures/fwup/fat.conf")
  @mixed File.read!("test/fixtures/fwup/mixed.conf")
  @pi_style File.read!("test/fixtures/fwup/pi-style.conf")
  @pi_style_delta File.read!("test/fixtures/fwup/pi-style-delta.conf")

  defp build_fw!(path, fwup_path, data_path) do
    case System.cmd("fwup", ["-c", "-f", fwup_path, "-o", path],
           stderr_to_stdout: true,
           env: [
             {"TEST_1", data_path}
           ]
         ) do
      {_, 0} ->
        path

      {output, _} ->
        flunk("Error in fwup:\n#{output}")
    end
  end

  defp complete!(fw_path, image_path) do
    case System.cmd("fwup", ["-a", "-d", image_path, "-i", fw_path, "-t", "complete"],
           stderr_to_stdout: true,
           env: []
         ) do
      {_, 0} ->
        image_path

      {output, _} ->
        flunk("Error in fwup:\n#{output}")
    end
  end

  defp upgrade!(fw_path, image_path) do
    case System.cmd("fwup", ["-a", "-d", image_path, "-i", fw_path, "-t", "upgrade"],
           stderr_to_stdout: true,
           env: []
         ) do
      {_, 0} ->
        image_path

      {output, _} ->
        File.cp!(image_path, "/tmp/a.img")
        flunk("Error in fwup:\n#{output}")
    end
  end

  defp sha256sum(path) do
    data = File.read!(path)
    :sha256 |> :crypto.hash(data) |> Base.encode64()
  end

  defp compare_images?({img_a, offset_a, size_a}, {img_b, offset_b, size_b}) do
    # fwup uses 512 byte blocks
    offset_a = offset_a * 512
    size_a = size_a * 512
    offset_b = offset_b * 512
    size_b = size_b * 512
    data_a = File.read!(img_a)
    data_b = File.read!(img_b)
    <<_::binary-size(offset_a), d1::binary-size(size_a), _::binary>> = data_a
    <<_::binary-size(offset_b), d2::binary-size(size_b), _::binary>> = data_b
    compare_data?(d1, d2, 0, true)
  end

  defp compare_data?(
         <<chunk_1::binary-size(512), d1::binary>>,
         <<chunk_2::binary-size(512), d2::binary>>,
         offset,
         valid?
       ) do
    valid? =
      if chunk_1 != chunk_2 do
        IO.puts("Difference at offset: #{offset} (#{trunc(offset / 512)})")
        IO.puts("chunk 1:")
        IO.puts(inspect(chunk_1, as: :binary, base: :hex))
        IO.puts("chunk 2:")
        IO.puts(inspect(chunk_2, as: :binary, base: :hex))
        IO.puts("")
        false
      else
        valid?
      end

    compare_data?(d1, d2, offset + 512, valid?)
  end

  defp compare_data?(<<chunk_1::binary>>, <<chunk_2::binary>>, offset, valid?) do
    if chunk_1 != chunk_2 do
      IO.puts("Difference at offset: #{offset} (#{trunc(offset / 512)})")
      IO.puts("chunk 1:")
      IO.inspect(chunk_1, as: :binary, base: :hex)
      IO.puts("chunk 2:")
      IO.inspect(chunk_2, as: :binary, base: :hex)
      IO.puts("")
      false
    else
      valid?
    end
  end

  @tag :tmp_dir
  test "generate valid delta for fat", %{tmp_dir: dir} do
    fwup_conf_path = Path.join(dir, "fwup.conf")
    File.write!(fwup_conf_path, @fat)

    data_path_1 = Path.join(dir, "data-1")
    data_1 = for _ <- 1..100, into: <<>>, do: Ecto.UUID.generate()
    File.write!(data_path_1, data_1)

    data_path_2 = Path.join(dir, "data-2")
    data_2 = for _ <- 1..100, into: data_1, do: Ecto.UUID.generate()
    File.write!(data_path_2, data_2)

    fw_a = build_fw!(Path.join(dir, "a.fw"), fwup_conf_path, data_path_1)
    fw_b = build_fw!(Path.join(dir, "b.fw"), fwup_conf_path, data_path_2)

    delta_path =
      Default.do_delta_file(fw_a, fw_b, Path.join(dir, "delta.fw"), Path.join(dir, "work"))

    %{size: b_size} = File.stat!(fw_b)
    %{size: delta_size} = File.stat!(delta_path)
    assert delta_size < b_size

    img_a = complete!(fw_a, Path.join(dir, "a.img"))
    hash_a = sha256sum(img_a)
    img_b = complete!(fw_b, Path.join(dir, "b.img"))
    hash_b = sha256sum(img_b)

    # fs images are different
    assert hash_a != hash_b

    upgrade!(delta_path, img_a)

    offset_a = 4096
    size_a = 154_476
    assert compare_images?({img_b, offset_a, size_a}, {img_a, offset_a + size_a, size_a})
  end

  @tag :tmp_dir
  test "generate valid delta for raw fwup config", %{tmp_dir: dir} do
    fwup_conf_path = Path.join(dir, "fwup.conf")
    File.write!(fwup_conf_path, @raw)

    data_path_1 = Path.join(dir, "data-1")
    data_1 = for _ <- 1..100, into: <<>>, do: Ecto.UUID.generate()
    File.write!(data_path_1, data_1)

    data_path_2 = Path.join(dir, "data-2")
    data_2 = for _ <- 1..100, into: data_1, do: Ecto.UUID.generate()
    File.write!(data_path_2, data_2)

    fw_a = build_fw!(Path.join(dir, "a.fw"), fwup_conf_path, data_path_1)
    fw_b = build_fw!(Path.join(dir, "b.fw"), fwup_conf_path, data_path_2)

    delta_path =
      Default.do_delta_file(fw_a, fw_b, Path.join(dir, "delta.fw"), Path.join(dir, "work"))

    %{size: b_size} = File.stat!(fw_b)
    %{size: delta_size} = File.stat!(delta_path)
    assert delta_size < b_size

    img_a = complete!(fw_a, Path.join(dir, "a.img"))
    hash_a = sha256sum(img_a)
    img_b = complete!(fw_b, Path.join(dir, "b.img"))
    hash_b = sha256sum(img_b)

    # fs images are different
    assert hash_a != hash_b

    upgrade!(delta_path, img_a)

    assert compare_images?({img_b, 1024, 1024}, {img_a, 2048, 1024})
  end

  @tag :tmp_dir
  test "generate valid delta for mixed fwup config", %{tmp_dir: dir} do
    fwup_conf_path = Path.join(dir, "fwup.conf")
    File.write!(fwup_conf_path, @mixed)

    data_path_1 = Path.join(dir, "data-1")
    data_1 = for _ <- 1..100, into: <<>>, do: Ecto.UUID.generate()
    File.write!(data_path_1, data_1)

    data_path_2 = Path.join(dir, "data-2")
    data_2 = for _ <- 1..100, into: data_1, do: Ecto.UUID.generate()
    File.write!(data_path_2, data_2)

    fw_a = build_fw!(Path.join(dir, "a.fw"), fwup_conf_path, data_path_1)
    fw_b = build_fw!(Path.join(dir, "b.fw"), fwup_conf_path, data_path_2)

    delta_path =
      Default.do_delta_file(fw_a, fw_b, Path.join(dir, "delta.fw"), Path.join(dir, "work"))

    %{size: b_size} = File.stat!(fw_b)
    %{size: delta_size} = File.stat!(delta_path)
    assert delta_size < b_size

    img_a = complete!(fw_a, Path.join(dir, "a.img"))
    hash_a = sha256sum(img_a)
    img_b = complete!(fw_b, Path.join(dir, "b.img"))
    hash_b = sha256sum(img_b)

    # fs images are different
    assert hash_a != hash_b

    upgrade!(delta_path, img_a)

    offset_a = 4096
    size_a = 154_476
    assert compare_images?({img_b, offset_a, size_a}, {img_a, offset_a + size_a, size_a})
    assert compare_images?({img_b, 1024, 1024}, {img_a, 2048, 1024})
  end

  @tag :tmp_dir
  test "verify that a firmware is delta updatable", %{tmp_dir: dir} do
    fwup_conf_path = Path.join(dir, "fwup.conf")
    File.write!(fwup_conf_path, @pi_style_delta)

    data_path_1 = Path.join(dir, "data-1")
    data_1 = for _ <- 1..100, into: <<>>, do: Ecto.UUID.generate()
    File.write!(data_path_1, data_1)

    data_path_2 = Path.join(dir, "data-2")
    data_2 = for _ <- 1..100, into: data_1, do: Ecto.UUID.generate()
    File.write!(data_path_2, data_2)

    fw_a = build_fw!(Path.join(dir, "a.fw"), fwup_conf_path, data_path_1)
    fw_b = build_fw!(Path.join(dir, "b.fw"), fwup_conf_path, data_path_2)

    delta_path =
      Default.do_delta_file(fw_a, fw_b, Path.join(dir, "delta.fw"), Path.join(dir, "work"))

    %{size: b_size} = File.stat!(fw_b)
    %{size: delta_size} = File.stat!(delta_path)
    assert delta_size < b_size

    img_a = complete!(fw_a, Path.join(dir, "a.img"))
    hash_a = sha256sum(img_a)
    img_b = complete!(fw_b, Path.join(dir, "b.img"))
    hash_b = sha256sum(img_b)

    # fs images are different
    assert hash_a != hash_b

    # Upgrade A to B
    upgrade!(delta_path, img_a)
    # Upgrading twice should make both slots identical
    upgrade!(delta_path, img_a)

    # Upgrade non-delta B to B, should make both slots identical
    upgrade!(fw_b, img_b)
    # Upgrade it again to match the slot situation/uboot-env
    upgrade!(fw_b, img_b)

    hash_a = sha256sum(img_a)
    hash_b = sha256sum(img_b)
    %{size: size_a} = File.stat!(img_a)
    # -32 to skip uboot
    fwup_size_a = trunc(size_a / 512) - 32
    %{size: size_b} = File.stat!(img_b)
    fwup_size_b = trunc(size_b / 512) - 32
    assert compare_images?({img_a, 32, fwup_size_a}, {img_b, 32, fwup_size_b})
    assert hash_a == hash_b
  end
end
