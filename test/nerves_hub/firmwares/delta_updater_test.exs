defmodule NervesHub.Firmwares.DeltaUpdateTest do
  use ExUnit.Case, async: true

  alias NervesHub.Firmwares.DeltaUpdater.Default

  @raw File.read!("test/fixtures/fwup/raw.conf")
  @fat File.read!("test/fixtures/fwup/fat.conf")
  @mixed File.read!("test/fixtures/fwup/mixed.conf")
  @mixed_no_deltas File.read!("test/fixtures/fwup/mixed-no-deltas.conf")
  @pi_style File.read!("test/fixtures/fwup/pi-style.conf")
  @pi_style_delta File.read!("test/fixtures/fwup/pi-style-delta.conf")

  setup_all do
    with path_1 when is_binary(path_1) <- System.find_executable("mdir"),
         path_2 when is_binary(path_2) <- System.find_executable("mcopy") do
      :ok
    else
      _ ->
        flunk("Please install mtools to run these tests.")
    end
  end

  defp offsets(start, parts_with_sizes) do
    {offsets, _} =
      parts_with_sizes
      |> Enum.reduce({[], start}, fn {field, size}, {fields, offset} ->
        fields = [{field, {offset, size}} | fields]
        {fields, offset + size}
      end)

    Enum.reverse(offsets)
  end

  defp build_fw!(path, fwup_path, data_path) do
    case System.cmd("fwup", ["-c", "-f", fwup_path, "-o", path],
           stderr_to_stdout: true,
           env: [
             {"TEST_1", data_path}
           ]
         ) do
      {_, 0} ->
        path

      {output, status} ->
        flunk("Error in fwup with status #{status}:\n#{output}")
    end
  end

  defp complete!(fw_path, image_path) do
    case System.cmd("fwup", ["-a", "-d", image_path, "-i", fw_path, "-t", "complete"],
           stderr_to_stdout: true,
           env: []
         ) do
      {_, 0} ->
        image_path

      {output, status} ->
        flunk("Error in fwup with status #{status}:\n#{output}")
    end
  end

  defp upgrade!(fw_path, image_path) do
    case System.cmd("fwup", ["-a", "-d", image_path, "-i", fw_path, "-t", "upgrade"],
           stderr_to_stdout: true,
           env: []
         ) do
      {_, 0} ->
        image_path

      {output, status} ->
        flunk("Error in fwup with status #{status}:\n#{output}")
    end
  end

  defp sha256sum(path) do
    data = File.read!(path)
    :sha256 |> :crypto.hash(data) |> Base.encode64()
  end

  defp mcopy(img_path, offset, files, to_dir) do
    File.mkdir_p(to_dir)

    file_args =
      files
      |> Enum.map(fn file ->
        "::#{file}"
      end)

    args = ["-i", "#{img_path}@@#{offset * 512}"] ++ file_args ++ [to_dir]
    {_output, 0} = System.cmd("mdir", ["-i", "#{img_path}@@#{offset * 512}"], env: [])

    {_, 0} =
      System.cmd("mcopy", args, env: [])
  end

  defp same_fat_files?(base_dir, {img_a, offset_a}, {img_b, offset_b}, files) do
    path_a = Path.join(base_dir, "fat_a")
    path_b = Path.join(base_dir, "fat_b")
    mcopy(img_a, offset_a, files, path_a)
    mcopy(img_b, offset_b, files, path_b)

    for file <- files do
      a = File.read!(Path.join(path_a, file))
      b = File.read!(Path.join(path_b, file))
      assert a == b
    end
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
        find_diff(chunk_1, chunk_2)
        false
      else
        valid?
      end

    compare_data?(d1, d2, offset + 512, valid?)
  end

  defp compare_data?(<<chunk_1::binary>>, <<chunk_2::binary>>, offset, valid?) do
    if chunk_1 != chunk_2 do
      IO.puts("Difference at final offset: #{offset} (#{trunc(offset / 512)})")
      find_diff(chunk_1, chunk_2)
      false
    else
      valid?
    end
  end

  defp find_diff(chunk_1, chunk_2, byte \\ 0) do
    case {chunk_1, chunk_2} do
      {<<b1::8, r1::binary>>, <<b2::8, r2::binary>>} when b1 == b2 ->
        find_diff(r1, r2, byte + 1)

      {<<b1::8, r1::binary>>, <<b2::8, r2::binary>>} when b1 != b2 ->
        IO.puts("#{byte} @\t\t#{h(b1)}  #{h(b2)}")
        find_diff(r1, r2, byte + 1)

      {<<>>, <<>>} ->
        :ok
    end
  end

  defp h(b), do: inspect(b, as: :binary, base: :hex)

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
    %{size: source_size} = File.stat!(fw_a)
    %{size: target_size} = File.stat!(fw_b)

    {:ok, delta_path,
     %{"size" => delta_size, "source_size" => ^source_size, "target_size" => ^target_size}} =
      Default.do_delta_file(fw_a, fw_b, Path.join(dir, "delta.fw"), Path.join(dir, "work"))

    assert %{size: ^delta_size} = File.stat!(delta_path)

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
    %{size: source_size} = File.stat!(fw_a)
    %{size: target_size} = File.stat!(fw_b)

    {:ok, delta_path,
     %{"size" => delta_size, "source_size" => ^source_size, "target_size" => ^target_size}} =
      Default.do_delta_file(fw_a, fw_b, Path.join(dir, "delta.fw"), Path.join(dir, "work"))

    assert %{size: ^delta_size} = File.stat!(delta_path)

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
  @tag :mtools
  test "generate valid delta for mixed fwup config", %{tmp_dir: dir} do
    fwup_conf_path = Path.join(dir, "fwup.conf")
    File.write!(fwup_conf_path, @mixed)

    data_path_1 = Path.join(dir, "data-1")
    data_1 = for _ <- 1..50_000, into: <<>>, do: Ecto.UUID.generate()
    File.write!(data_path_1, data_1)

    data_path_2 = Path.join(dir, "data-2")
    new_data_2 = for _ <- 1..50_000, into: <<>>, do: Ecto.UUID.generate()
    data_2 = data_1 <> new_data_2
    File.write!(data_path_2, data_2)

    fw_a = build_fw!(Path.join(dir, "a.fw"), fwup_conf_path, data_path_1)
    fw_b = build_fw!(Path.join(dir, "b.fw"), fwup_conf_path, data_path_2)
    %{size: source_size} = File.stat!(fw_a)
    %{size: target_size} = File.stat!(fw_b)

    {:ok, delta_path,
     %{"size" => delta_size, "source_size" => ^source_size, "target_size" => ^target_size}} =
      Default.do_delta_file(fw_a, fw_b, Path.join(dir, "delta.fw"), Path.join(dir, "work"))

    assert %{size: ^delta_size} = File.stat!(delta_path)

    img_a = complete!(fw_a, Path.join(dir, "a.img"))
    hash_a = sha256sum(img_a)
    img_b = complete!(fw_b, Path.join(dir, "b.img"))
    hash_b = sha256sum(img_b)

    # fs images are different
    assert hash_a != hash_b

    upgrade!(delta_path, img_a)

    boot_size = 154_476
    root_size = 20_480

    [
      boot_a: {boot_a_offset, _boot_a_size},
      boot_b: {boot_b_offset, _boot_b_size},
      root_a: {root_a_offset, root_a_size},
      root_b: {root_b_offset, root_b_size}
    ] =
      offsets(4096,
        boot_a: boot_size,
        boot_b: boot_size,
        root_a: root_size,
        root_b: root_size
      )

    # Validate Boot A having been patched to match Boot B
    assert same_fat_files?(dir, {img_a, boot_b_offset}, {img_b, boot_a_offset}, ["second"])

    # Validate Root A having been patched to match Root B
    assert compare_images?(
             {img_b, root_a_offset, root_a_size},
             {img_a, root_b_offset, root_b_size}
           )
  end

  @tag :tmp_dir
  test "do not generate deltas if not enabled", %{tmp_dir: dir} do
    fwup_conf_path = Path.join(dir, "fwup.conf")
    File.write!(fwup_conf_path, @mixed_no_deltas)

    data_path_1 = Path.join(dir, "data-1")
    data_1 = for _ <- 1..50_000, into: <<>>, do: Ecto.UUID.generate()
    File.write!(data_path_1, data_1)

    data_path_2 = Path.join(dir, "data-2")
    new_data_2 = for _ <- 1..50_000, into: <<>>, do: Ecto.UUID.generate()
    data_2 = data_1 <> new_data_2
    File.write!(data_path_2, data_2)

    fw_a = build_fw!(Path.join(dir, "a.fw"), fwup_conf_path, data_path_1)
    fw_b = build_fw!(Path.join(dir, "b.fw"), fwup_conf_path, data_path_2)

    {:error, :no_delta_support_in_firmware} =
      Default.do_delta_file(fw_a, fw_b, Path.join(dir, "delta.fw"), Path.join(dir, "work"))
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
    %{size: source_size} = File.stat!(fw_a)
    %{size: target_size} = File.stat!(fw_b)

    {:ok, delta_path,
     %{"size" => delta_size, "source_size" => ^source_size, "target_size" => ^target_size}} =
      Default.do_delta_file(fw_a, fw_b, Path.join(dir, "delta.fw"), Path.join(dir, "work"))

    %{size: ^delta_size} = File.stat!(delta_path)

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

  @tag :tmp_dir
  @tag :mtools
  test "verify that a firmware is not delta updatable but file generated is okay", %{tmp_dir: dir} do
    fwup_conf_path = Path.join(dir, "fwup.conf")
    File.write!(fwup_conf_path, @pi_style)

    data_path_1 = Path.join(dir, "data-1")
    data_1 = for _ <- 1..100, into: <<>>, do: Ecto.UUID.generate()
    File.write!(data_path_1, data_1)

    data_path_2 = Path.join(dir, "data-2")
    data_2 = for _ <- 1..100, into: data_1, do: Ecto.UUID.generate()
    File.write!(data_path_2, data_2)

    fw_a = build_fw!(Path.join(dir, "a.fw"), fwup_conf_path, data_path_1)
    fw_b = build_fw!(Path.join(dir, "b.fw"), fwup_conf_path, data_path_2)

    %{size: source_size} = File.stat!(fw_a)
    %{size: target_size} = File.stat!(fw_b)

    {:ok, delta_path,
     %{"size" => delta_size, "source_size" => ^source_size, "target_size" => ^target_size}} =
      Default.do_delta_file(fw_a, fw_b, Path.join(dir, "delta.fw"), Path.join(dir, "work"))

    assert %{size: ^delta_size} = File.stat!(delta_path)

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

    boot_size = 77_260
    root_size = 57_8088
    app_size = 1_048_576

    [
      boot_a: {boot_a_offset, _boot_a_size},
      boot_b: {boot_b_offset, _boot_b_size},
      root_a: {root_a_offset, _root_a_size},
      root_b: {root_b_offset, _root_b_size},
      app: {_, _}
    ] =
      offsets(63,
        boot_a: boot_size,
        boot_b: boot_size,
        root_a: root_size,
        root_b: root_size,
        app: app_size
      )

    # Validate Boot A having been patched to match Boot B
    assert same_fat_files?(dir, {img_a, boot_b_offset}, {img_b, boot_a_offset}, ["first"])
    assert compare_images?({img_a, root_b_offset, root_size}, {img_b, root_a_offset, root_size})
  end
end
