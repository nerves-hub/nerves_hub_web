defmodule NervesHub.Workers.FirmwareDeltaBuilderTest do
  use NervesHub.DataCase, async: true
  use Mimic

  alias NervesHub.Firmwares
  alias NervesHub.Firmwares.UpdateTool.Fwup
  alias NervesHub.Fixtures
  alias NervesHub.Repo
  alias NervesHub.Workers.FirmwareDeltaBuilder

  defp capture_xdelta3_args() do
    stub(System, :cmd, fn
      "xdelta3" = cmd, args, opts ->
        send(self(), {:xdelta3_args, args})
        Mimic.call_original(System, :cmd, [cmd, args, opts])

      cmd, args, opts ->
        Mimic.call_original(System, :cmd, [cmd, args, opts])
    end)
  end

  defp receive_xdelta3_args() do
    receive do
      {:xdelta3_args, args} -> args
    after
      0 -> flunk("expected xdelta3 to be called but it wasn't")
    end
  end

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)

    %{user: user, org: org, product: product, org_key: org_key}
  end

  describe "perform/1 - real integration tests" do
    test "successfully generates real delta firmware end-to-end", %{
      org_key: org_key,
      product: product,
      tmp_dir: tmp_dir
    } do
      # Set up Req.Test to intercept HTTP requests
      # (plug is configured in config/test.exs)
      Req.Test.stub(NervesHub, fn conn ->
        # Extract UUID from the request path
        # Expected format: http://localhost:1234/firmware/{org_id}/{uuid}.fw
        case Regex.run(~r|/firmware/\d+/([a-f0-9-]+)\.fw$|, conn.request_path) do
          [_full, uuid] ->
            # Find firmware by UUID and serve the local file
            case Repo.get_by(Firmwares.Firmware, uuid: uuid) do
              firmware ->
                # Get local path from upload_metadata
                local_path =
                  firmware.upload_metadata["local_path"] || firmware.upload_metadata[:local_path]

                # Read and send the file
                body = File.read!(local_path)

                conn
                |> Plug.Conn.put_resp_content_type("application/octet-stream")
                |> Plug.Conn.send_resp(200, body)
            end
        end
      end)

      # Use a shared resource name so both firmwares have compatible resources
      shared_resource = "shared-resource-#{System.unique_integer([:positive])}"

      # Create source and target firmwares with delta_updatable = true
      # Use larger content to ensure we're above the 22-byte delta overhead limit
      source_firmware =
        Fixtures.firmware_fixture(org_key, product, %{
          version: "1.0.0",
          resource_name: shared_resource,
          resource_contents: String.duplicate("source file contents ", 100),
          dir: tmp_dir
        })
        |> Ecto.Changeset.change(delta_updatable: true)
        |> Repo.update!()

      target_firmware =
        Fixtures.firmware_fixture(org_key, product, %{
          version: "2.0.0",
          resource_name: shared_resource,
          resource_contents: String.duplicate("target file contents with extra data ", 100),
          dir: tmp_dir
        })
        |> Ecto.Changeset.change(delta_updatable: true)
        |> Repo.update!()

      {:ok, delta} = Firmwares.start_firmware_delta(source_firmware.id, target_firmware.id)

      assert :ok ==
               FirmwareDeltaBuilder.perform(%Oban.Job{
                 id: Ecto.UUID.generate(),
                 attempt: 1,
                 args: %{
                   "source_id" => source_firmware.id,
                   "target_id" => target_firmware.id
                 }
               })

      # Verify delta was successfully generated
      delta = Repo.reload(delta)
      assert delta.status == :completed
      assert delta.size > 0

      assert Enum.empty?(:ets.tab2list(Briefly.Entry.Path)),
             "Work directory should be cleaned up after delta generation"
    end

    test "marks delta as failed on final attempt", %{
      org_key: org_key,
      product: product,
      tmp_dir: tmp_dir
    } do
      stub(Fwup, :create_firmware_delta_file, fn _, _, _ -> {:error, :test_failure} end)

      source_firmware =
        Fixtures.firmware_fixture(org_key, product, %{version: "1.0.0", dir: tmp_dir})
        |> Ecto.Changeset.change(delta_updatable: true)
        |> Repo.update!()

      target_firmware =
        Fixtures.firmware_fixture(org_key, product, %{version: "2.0.0", dir: tmp_dir})
        |> Ecto.Changeset.change(delta_updatable: true)
        |> Repo.update!()

      # Delete files to cause failure
      NervesHub.Firmwares.Upload.File.delete_file(source_firmware.upload_metadata)
      NervesHub.Firmwares.Upload.File.delete_file(target_firmware.upload_metadata)

      {:ok, delta} = Firmwares.start_firmware_delta(source_firmware.id, target_firmware.id)

      job = %Oban.Job{
        id: Ecto.UUID.generate(),
        attempt: 3,
        max_attempts: 3,
        args: %{
          "source_id" => source_firmware.id,
          "target_id" => target_firmware.id
        }
      }

      assert {:error, :test_failure} = FirmwareDeltaBuilder.perform(job)

      delta = Repo.reload(delta)
      assert delta.status == :failed
    end

    test "retries without marking failed on non-final attempts", %{
      org_key: org_key,
      product: product,
      tmp_dir: tmp_dir
    } do
      stub(Fwup, :create_firmware_delta_file, fn _, _, _ -> {:error, :test_failure} end)

      source_firmware =
        Fixtures.firmware_fixture(org_key, product, %{version: "1.0.0", dir: tmp_dir})
        |> Ecto.Changeset.change(delta_updatable: true)
        |> Repo.update!()

      target_firmware =
        Fixtures.firmware_fixture(org_key, product, %{version: "2.0.0", dir: tmp_dir})
        |> Ecto.Changeset.change(delta_updatable: true)
        |> Repo.update!()

      NervesHub.Firmwares.Upload.File.delete_file(source_firmware.upload_metadata)
      NervesHub.Firmwares.Upload.File.delete_file(target_firmware.upload_metadata)

      {:ok, delta} = Firmwares.start_firmware_delta(source_firmware.id, target_firmware.id)

      job = %Oban.Job{
        id: Ecto.UUID.generate(),
        attempt: 2,
        args: %{
          "source_id" => source_firmware.id,
          "target_id" => target_firmware.id
        }
      }

      # Worker returns {:error, ...} on failure
      assert {:error, :test_failure} = FirmwareDeltaBuilder.perform(job)

      delta = Repo.reload(delta)
      assert delta.status == :processing, "Should remain processing for retry"
    end
  end

  describe "perform/1 - xdelta3 source window (-B flag)" do
    setup %{tmp_dir: tmp_dir} do
      Req.Test.stub(NervesHub, fn conn ->
        case Regex.run(~r|/firmware/\d+/([a-f0-9-]+)\.fw$|, conn.request_path) do
          [_full, uuid] ->
            firmware = Repo.get_by(Firmwares.Firmware, uuid: uuid)
            local_path = firmware.upload_metadata["local_path"] || firmware.upload_metadata[:local_path]
            body = File.read!(local_path)

            conn
            |> Plug.Conn.put_resp_content_type("application/octet-stream")
            |> Plug.Conn.send_resp(200, body)
        end
      end)

      shared_resource = "shared-resource-#{System.unique_integer([:positive])}"
      %{shared_resource: shared_resource, tmp_dir: tmp_dir}
    end

    # NOTE: Testing actual output from xdelta3 is a bit overkill so we just check that the flag exists as expected.
    test "passes -B <bytes> to xdelta3 when target conf has block-cache-size-mb", %{
      org_key: org_key,
      product: product,
      shared_resource: shared_resource,
      tmp_dir: tmp_dir
    } do
      source_firmware =
        Fixtures.firmware_fixture(org_key, product, %{
          version: "1.0.0",
          resource_name: shared_resource,
          resource_contents: String.duplicate("source file contents ", 100),
          dir: tmp_dir
        })
        |> Ecto.Changeset.change(delta_updatable: true)
        |> Repo.update!()

      target_firmware =
        Fixtures.firmware_fixture(org_key, product, %{
          version: "2.0.0",
          resource_name: shared_resource,
          resource_contents: String.duplicate("target file contents with extra data ", 100),
          block_cache_size_mb: 128,
          dir: tmp_dir
        })
        |> Ecto.Changeset.change(delta_updatable: true)
        |> Repo.update!()

      {:ok, delta} = Firmwares.start_firmware_delta(source_firmware.id, target_firmware.id)

      capture_xdelta3_args()

      assert :ok ==
               FirmwareDeltaBuilder.perform(%Oban.Job{
                 id: Ecto.UUID.generate(),
                 attempt: 1,
                 args: %{"source_id" => source_firmware.id, "target_id" => target_firmware.id}
               })

      delta = Repo.reload(delta)
      assert delta.status == :completed

      args = receive_xdelta3_args()
      expected_window = Integer.to_string(128 * 1024 * 1024)
      b_index = Enum.find_index(args, &(&1 == "-B"))

      assert b_index != nil, "expected -B flag in xdelta3 args, got: #{inspect(args)}"
      assert Enum.at(args, b_index + 1) == expected_window
    end

    test "does not pass -B to xdelta3 when target conf lacks block-cache-size-mb", %{
      org_key: org_key,
      product: product,
      shared_resource: shared_resource,
      tmp_dir: tmp_dir
    } do
      source_firmware =
        Fixtures.firmware_fixture(org_key, product, %{
          version: "1.0.0",
          resource_name: shared_resource,
          resource_contents: String.duplicate("source file contents ", 100),
          dir: tmp_dir
        })
        |> Ecto.Changeset.change(delta_updatable: true)
        |> Repo.update!()

      target_firmware =
        Fixtures.firmware_fixture(org_key, product, %{
          version: "2.0.0",
          resource_name: shared_resource,
          resource_contents: String.duplicate("target file contents with extra data ", 100),
          dir: tmp_dir
        })
        |> Ecto.Changeset.change(delta_updatable: true)
        |> Repo.update!()

      {:ok, delta} = Firmwares.start_firmware_delta(source_firmware.id, target_firmware.id)

      capture_xdelta3_args()

      assert :ok ==
               FirmwareDeltaBuilder.perform(%Oban.Job{
                 id: Ecto.UUID.generate(),
                 attempt: 1,
                 args: %{"source_id" => source_firmware.id, "target_id" => target_firmware.id}
               })

      delta = Repo.reload(delta)
      assert delta.status == :completed

      args = receive_xdelta3_args()
      refute "-B" in args, "expected no -B flag in xdelta3 args, got: #{inspect(args)}"
    end
  end
end
