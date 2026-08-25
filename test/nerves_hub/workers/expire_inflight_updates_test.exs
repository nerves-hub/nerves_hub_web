defmodule NervesHub.Workers.ExpireInflightUpdatesTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Devices.InflightUpdate
  alias NervesHub.Workers.ExpireInflightUpdates

  describe "perform/1" do
    test "returns :ok when called" do
      job = %Oban.Job{id: Ecto.UUID.generate(), attempt: 1, args: %{}}
      assert :ok = ExpireInflightUpdates.perform(job)
    end
  end

  describe "prod?/0" do
    test "returns false in test environment" do
      refute ExpireInflightUpdates.prod?()
    end
  end

  describe "perform/1 with expired inflight updates" do
    @moduletag :tmp_dir

    test "deletes inflight updates that haven't been updated in 30+ minutes", %{tmp_dir: tmp_dir} do
      alias NervesHub.Fixtures
      alias NervesHub.Repo

      user = Fixtures.user_fixture()
      org = Fixtures.org_fixture(user)
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      device = Fixtures.device_fixture(org, product, firmware)

      past = DateTime.utc_now() |> DateTime.add(-35, :minute) |> DateTime.truncate(:second)

      {1, _} =
        Repo.insert_all(
          "inflight_updates",
          [
            %{
              device_id: device.id,
              firmware_id: firmware.id,
              status: "updating",
              inserted_at: past,
              updated_at: past
            }
          ]
        )

      assert :ok = ExpireInflightUpdates.perform(%Oban.Job{id: 1, attempt: 1, args: %{}})

      assert Repo.all(InflightUpdate) == []
    end
  end
end
