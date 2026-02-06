defmodule NervesHub.Firmwares.UpdateTool.Fwup do
  @moduledoc """
  Default NervesHub.Firmwares.UpdateTool implementation, providing fwup support.
  """

  @behaviour NervesHub.Firmwares.UpdateTool

  alias NervesHub.Devices.Device
  alias NervesHub.Firmwares
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Firmwares.UpdateTool
  alias NervesHub.Fwup, as: FwupUtil
  alias NervesHub.Helpers.Logging

  require Logger

  @very_safe_version "1.13.0"
  @oldest_version Version.parse!("0.2.0")

  # If a payload is smaller than this there is no point to do a delta, the overhead takes more space
  # in the best case
  @delta_overhead_limit 22

  @impl UpdateTool
  def get_firmware_metadata_from_file(filepath) do
    with {:ok, firmware_metadata} <- FwupUtil.metadata(filepath),
         {:ok, meta_conf_path} <- extract_meta_conf_locally(filepath),
         {:ok, tool_metadata} <- get_tool_metadata(meta_conf_path) do
      {:ok,
       %{
         path: meta_conf_path,
         firmware_metadata: firmware_metadata,
         tool_metadata: tool_metadata,
         tool: "fwup",
         tool_delta_required_version: tool_metadata.delta_fwup_version,
         tool_full_required_version: tool_metadata.complete_fwup_version
       }}
    end
  end

  @impl UpdateTool
  def get_firmware_metadata_from_upload(firmware) do
    case download_archive(firmware) do
      {:ok, filepath} -> get_firmware_metadata_from_file(filepath)
      err -> err
    end
  end

  @impl UpdateTool
  def create_firmware_delta_file({source_uuid, source_url}, {target_uuid, target_url}) do
    work_dir = Path.join(System.tmp_dir(), "#{source_uuid}_#{target_uuid}")
    _ = File.mkdir_p(work_dir)

    try do
      source_path = Path.join(work_dir, "source.fw") |> Path.expand()
      target_path = Path.join(work_dir, "target.fw") |> Path.expand()

      dl!(source_url, source_path)
      dl!(target_url, target_path)

      case do_delta_file({source_uuid, source_path}, {target_uuid, target_path}, work_dir) do
        {:ok, output} ->
          {:ok, output}

        {:error, reason} ->
          Logger.warning("Firmware delta creation failed: #{inspect(reason)}",
            source_url: source_url,
            target_url: target_url
          )

          {:error, reason}
      end
    rescue
      e ->
        Logger.warning(
          "Firmware delta creation failed with exception: #{inspect(e)}, stacktrace: #{inspect(__STACKTRACE__)}",
          source_url: source_url,
          target_url: target_url
        )

        {:error, :download_or_delta_failed}
    after
      File.rm_rf(work_dir)
    end
  end

  @impl UpdateTool
  def cleanup_firmware_delta_files(firmware_delta_path) do
    Path.dirname(firmware_delta_path)
    |> File.rm_rf()
    |> case do
      {:ok, _} ->
        :ok

      {:error, reason, _path} ->
        Logging.log_message_to_sentry("Could not cleanup delta files", %{reason: reason})

        :ok
    end
  end

  @impl UpdateTool
  def delta_updatable?(file_path) do
    {:ok, feature_usage} = Confuse.Fwup.get_feature_usage(file_path)

    feature_usage.raw_deltas? or feature_usage.fat_deltas?
  end

  @impl UpdateTool
  def device_update_type(%Device{firmware_metadata: fw_meta} = device, %Firmware{} = target) do
    # Unknown version, assume oldest
    device_fwup_version = device.firmware_metadata.fwup_version || @oldest_version

    %{product_id: product_id, firmware_metadata: %{uuid: firmware_uuid}} = device

    with {:source, {:ok, source}} <-
           {:source, Firmwares.get_firmware_by_product_id_and_uuid(product_id, firmware_uuid)},
         {:delta_result, {:ok, %{tool_metadata: tm}}} <-
           {:delta_result, Firmwares.get_firmware_delta_by_source_and_target(source.id, target.id)},
         {:delta_min, delta_min} <-
           {:delta_min, Map.get(tm, "delta_fwup_version", @very_safe_version)},
         {:parse_version, {:ok, delta_version}} <- {:parse_version, Version.parse(delta_min)},
         {:acceptable, true} <-
           {:acceptable, version_acceptable?(delta_version, device_fwup_version)} do
      :delta
    else
      err ->
        Logger.info("Disqualified from delta update due to: #{inspect(err)}")
        :full
    end
  rescue
    e ->
      Logging.log_to_sentry(
        device,
        "[UpdateTool.Fwup] Error fetching device update type: #{inspect(e)}",
        %{target_firmware_uuid: target.uuid, source_firmware_uuid: Map.get(fw_meta, :uuid)}
      )

      Logger.error("Error fetching device update type: #{inspect(e)}",
        target_firmware_uuid: target.uuid,
        source_firmware_uuid: Map.get(fw_meta, :uuid)
      )

      :full
  end

  defp version_acceptable?(v1, v2) do
    (Version.compare(v1, v2) in [:lt, :eq])
    |> tap(fn acceptable? ->
      if not acceptable? do
        Logger.info("Version not acceptable: #{v1} > #{v2}")
      end
    end)
  end

  def do_delta_file({source_uuid, source_path}, {target_uuid, target_path}, work_dir) do
    source_work_dir = Path.join(work_dir, "source")
    target_work_dir = Path.join(work_dir, "target")
    output_work_dir = Path.join(work_dir, "output")

    with :ok <- File.mkdir_p(work_dir),
         :ok <- File.mkdir_p(source_work_dir),
         :ok <- File.mkdir_p(target_work_dir),
         :ok <- File.mkdir_p(output_work_dir),
         {:ok, %{size: source_size}} <- File.stat(source_path),
         {:ok, %{size: target_size}} <- File.stat(target_path),
         {:ok, _} <- :zip.extract(to_charlist(source_path), cwd: to_charlist(source_work_dir)),
         {:ok, _} <- :zip.extract(to_charlist(target_path), cwd: to_charlist(target_work_dir)),
         {:ok, source_meta_conf} <- File.read(Path.join(source_work_dir, "meta.conf")),
         {:ok, target_meta_conf} <- File.read(Path.join(target_work_dir, "meta.conf")),
         {:ok, tool_metadata} <- get_tool_metadata(Path.join(target_work_dir, "meta.conf")),
         :ok <- Confuse.Fwup.validate_delta(source_meta_conf, target_meta_conf),
         {:ok, deltas} <- Confuse.Fwup.get_delta_files_from_config(target_meta_conf),
         {:ok, all_delta_files} <- delta_files(deltas) do
      Logger.info("Generating delta for files: #{Enum.join(all_delta_files, ", ")}")

      file_list =
        for absolute <- Path.wildcard(target_work_dir <> "/**"), not File.dir?(absolute) do
          path = Path.relative_to(absolute, target_work_dir)

          output_path = Path.join(output_work_dir, path)

          output_path
          |> Path.dirname()
          |> File.mkdir_p!()

          maybe_generate_delta(
            path,
            source_work_dir,
            target_work_dir,
            output_work_dir,
            all_delta_files
          )
        end
        |> Enum.reject(&is_nil/1)

      {:ok, delta_zip_path} = Plug.Upload.random_file("#{source_uuid}_#{target_uuid}_delta.zip")
      _ = File.rm(delta_zip_path)
      _ = File.cp(target_path, delta_zip_path)

      with {true, :changes_in_delta} <- {Enum.any?(file_list), :changes_in_delta},
           :ok <- update_changed_files(file_list, delta_zip_path, output_work_dir),
           {:ok, %{size: delta_size}} <- File.stat(delta_zip_path),
           {true, :delta_smaller} <- {delta_size < target_size, :delta_smaller} do
        {:ok,
         %{
           filepath: delta_zip_path,
           size: delta_size,
           source_size: source_size,
           target_size: target_size,
           tool: "fwup",
           tool_metadata: tool_metadata
         }}
      else
        {false, :changes_in_delta} -> {:error, :no_changes_in_delta}
        {false, :delta_smaller} -> {:error, :delta_larger_than_target}
      end
    end
  end

  defp update_changed_files(file_list, delta_zip_path, output_work_dir) do
    for file <- file_list do
      args = ["-9", delta_zip_path, String.replace_prefix(file, "#{output_work_dir}/", "")]
      {_output, 0} = System.cmd("zip", args, cd: output_work_dir, env: [])
    end

    :ok
  end

  defp maybe_generate_delta("meta." <> _, _, _, _, _) do
    nil
  end

  defp maybe_generate_delta(
         "data/" <> subpath = path,
         source_work_dir,
         target_work_dir,
         output_work_dir,
         all_delta_files
       ) do
    output_path = Path.join(output_work_dir, path)
    target_filepath = Path.join(target_work_dir, path)

    if subpath in all_delta_files do
      source_filepath = Path.join(source_work_dir, path)

      case File.stat(source_filepath) do
        {:ok, %{size: f_source_size}} ->
          args = ["-A", "-S", "-f", "-s", source_filepath, target_filepath, output_path]
          %{size: f_target_size} = File.stat!(target_filepath)

          if f_target_size < @delta_overhead_limit do
            Logger.info("Skipping generating delta for #{path} it is under 22 bytes.")
            nil
          else
            generate_and_validate_delta(path, args, output_path, f_source_size, f_target_size)
          end

        {:error, :enoent} ->
          nil
      end
    end
  end

  defp generate_and_validate_delta(path, args, output_path, f_source_size, f_target_size) do
    {_, 0} = System.cmd("xdelta3", args, stderr_to_stdout: true, env: %{})
    %{size: f_delta_size} = File.stat!(output_path)

    if f_delta_size < f_target_size do
      Logger.info(
        "Generated delta for #{path}, from #{Float.round(f_source_size / 1024 / 1024, 1)} MB to #{Float.round(f_target_size / 1024 / 1024, 1)} MB via delta of #{Float.round(f_delta_size / 1024 / 1024, 1)} MB"
      )

      output_path
    else
      Logger.info(
        "Skipping generated delta for #{path}, delta is larger: #{Float.round(f_source_size / 1024 / 1024, 1)} MB to #{Float.round(f_target_size / 1024 / 1024, 1)} MB via delta of #{Float.round(f_delta_size / 1024 / 1024, 1)} MB"
      )

      nil
    end
  end

  defp delta_files(deltas) do
    deltas
    |> Enum.flat_map(fn {_k, files} -> files end)
    |> Enum.uniq()
    |> case do
      [] -> {:error, :no_delta_support_in_firmware}
      delta_files -> {:ok, delta_files}
    end
  end

  defp get_tool_metadata(meta_conf_path) do
    with {:ok, feature_usage} <- Confuse.Fwup.get_feature_usage(meta_conf_path) do
      tool_metadata =
        for {key, value} <- Map.from_struct(feature_usage), into: %{} do
          case value do
            %Version{} ->
              {key, Version.to_string(value)}

            _ ->
              {key, value}
          end
        end

      {:ok, tool_metadata}
    end
  end

  defp extract_meta_conf_locally(filepath) do
    {:ok, path} = Plug.Upload.random_file("nerves_hub_meta_conf")

    stream = File.stream!(path)

    {:ok, unzip} =
      filepath
      |> Unzip.LocalFile.open()
      |> Unzip.new()

    _ =
      unzip
      |> Unzip.file_stream!("meta.conf")
      |> Enum.into(stream, &IO.iodata_to_binary/1)

    {:ok, path}
  rescue
    e ->
      Logging.log_message_to_sentry(
        "[UpdateTool.Fwup] Extracting meta.conf failed due to: #{inspect(e)}",
        %{filepath: filepath}
      )

      Logger.error("Extracting meta.conf failed due to: #{inspect(e)}", filepath: filepath)
      {:error, :extract_meta_conf_failed}
  end

  defp download_archive(firmware) do
    {:ok, url} = firmware_upload_config().download_file(firmware)
    {:ok, archive_path} = Plug.Upload.random_file("downloaded_firmware_#{firmware.id}")
    dl!(url, archive_path)
    {:ok, archive_path}
  rescue
    e ->
      Logging.log_message_to_sentry(
        "[UpdateTool.Fwup] Downloading firmware failed due to: #{inspect(e)}",
        %{firmware_uuid: firmware.uuid}
      )

      Logger.error("Downloading firmware failed due to: #{inspect(e)}, stacktrace: #{inspect(__STACKTRACE__)}",
        firmware_uuid: firmware.uuid
      )

      {:error, :download_firmware_failed}
  end

  defp firmware_upload_config(), do: Application.fetch_env!(:nerves_hub, :firmware_upload)

  defp dl!(url, filepath) do
    # Download and write to file
    response = Req.get!(url, Application.get_env(:nerves_hub, :firmware_download_options, []))

    if response.status != 200 do
      raise "HTTP download failed with status #{response.status}"
    end

    File.write!(filepath, response.body)

    :ok
  end
end
