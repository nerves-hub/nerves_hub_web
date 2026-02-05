defmodule NervesHub.Workers.FirmwareDeltaBuilderTest do
  use NervesHub.DataCase, async: true
  use Mimic

  alias NervesHub.Firmwares
  alias NervesHub.Firmwares.UpdateTool.Fwup
  alias NervesHub.Fixtures
  alias NervesHub.Repo
  alias NervesHub.Workers.FirmwareDeltaBuilder

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user)

    %{user: user, org: org, product: product, org_key: org_key}
  end

  describe "perform/1 - real integration tests" do
    test "successfully generates real delta firmware end-to-end", %{
      org_key: org_key,
      product: product
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
              nil ->
                Plug.Conn.send_resp(conn, 404, Jason.encode!(%{error: "not found"}))

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

          nil ->
            Plug.Conn.send_resp(conn, 404, Jason.encode!(%{error: "invalid path"}))
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
          resource_contents: String.duplicate("source file contents ", 100)
        })
        |> Ecto.Changeset.change(delta_updatable: true)
        |> Repo.update!()

      target_firmware =
        Fixtures.firmware_fixture(org_key, product, %{
          version: "2.0.0",
          resource_name: shared_resource,
          resource_contents: String.duplicate("target file contents with extra data ", 100)
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

      # Verify cleanup - work directory should no longer exist
      work_dir =
        Path.join(System.tmp_dir(), "#{source_firmware.uuid}_#{target_firmware.uuid}")

      refute File.exists?(work_dir),
             "Work directory should be cleaned up after delta generation"
    end

    test "marks delta as failed on final attempt", %{
      org_key: org_key,
      product: product
    } do
      stub(Fwup, :create_firmware_delta_file, fn _, _ -> {:error, :test_failure} end)

      source_firmware =
        Fixtures.firmware_fixture(org_key, product, %{version: "1.0.0"})
        |> Ecto.Changeset.change(delta_updatable: true)
        |> Repo.update!()

      target_firmware =
        Fixtures.firmware_fixture(org_key, product, %{version: "2.0.0"})
        |> Ecto.Changeset.change(delta_updatable: true)
        |> Repo.update!()

      # Delete files to cause failure
      NervesHub.Firmwares.Upload.File.delete_file(source_firmware.upload_metadata)
      NervesHub.Firmwares.Upload.File.delete_file(target_firmware.upload_metadata)

      {:ok, delta} = Firmwares.start_firmware_delta(source_firmware.id, target_firmware.id)

      job = %Oban.Job{
        id: Ecto.UUID.generate(),
        attempt: 5,
        args: %{
          "source_id" => source_firmware.id,
          "target_id" => target_firmware.id
        }
      }

      # Worker returns {:error, ...} on failure
      result = FirmwareDeltaBuilder.perform(job)
      assert match?({:error, _}, result) or match?(:error, result)

      delta = Repo.reload(delta)
      assert delta.status == :failed
    end

    test "retries without marking failed on non-final attempts", %{
      org_key: org_key,
      product: product
    } do
      stub(Fwup, :create_firmware_delta_file, fn _, _ -> {:error, :test_failure} end)

      source_firmware =
        Fixtures.firmware_fixture(org_key, product, %{version: "1.0.0"})
        |> Ecto.Changeset.change(delta_updatable: true)
        |> Repo.update!()

      target_firmware =
        Fixtures.firmware_fixture(org_key, product, %{version: "2.0.0"})
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
      result = FirmwareDeltaBuilder.perform(job)
      assert match?({:error, _}, result) or match?(:error, result)

      delta = Repo.reload(delta)
      assert delta.status == :processing, "Should remain processing for retry"
    end
  end
end
