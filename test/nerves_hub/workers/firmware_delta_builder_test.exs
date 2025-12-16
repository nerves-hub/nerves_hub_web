defmodule NervesHub.Workers.FirmwareDeltaBuilderTest do
  use NervesHub.DataCase
  use Mimic

  alias NervesHub.Firmwares
  alias NervesHub.Fixtures
  alias NervesHub.Workers.FirmwareDeltaBuilder

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user)
    source_firmware = Fixtures.firmware_fixture(org_key, product)
    target_firmware = Fixtures.firmware_fixture(org_key, product)

    %{source_firmware: source_firmware, target_firmware: target_firmware}
  end

  describe "test/1" do
    test "fails delta on last attempt", %{
      source_firmware: source_firmware,
      target_firmware: target_firmware
    } do
      delta =
        Fixtures.firmware_delta_fixture(source_firmware, target_firmware, %{status: :processing})

      expect(Firmwares, :generate_firmware_delta, fn _, _, _ -> {:error, :some_error} end)

      assert {:error, :some_error} =
               FirmwareDeltaBuilder.perform(%Oban.Job{
                 id: Ecto.UUID.generate(),
                 attempt: 5,
                 args: %{"source_id" => source_firmware.id, "target_id" => target_firmware.id}
               })

      assert Repo.reload(delta) |> Map.get(:status) == :failed
    end
  end

  test "fails delta immediately on no valid delta", %{
    source_firmware: source_firmware,
    target_firmware: target_firmware
  } do
    delta =
      Fixtures.firmware_delta_fixture(source_firmware, target_firmware, %{status: :processing})

    expect(Firmwares, :generate_firmware_delta, fn _, _, _ ->
      {:error, :no_delta_support_in_firmware}
    end)

    assert :discard =
             FirmwareDeltaBuilder.perform(%Oban.Job{
               id: Ecto.UUID.generate(),
               attempt: 1,
               args: %{"source_id" => source_firmware.id, "target_id" => target_firmware.id}
             })

    assert Repo.reload(delta) |> Map.get(:status) == :failed
  end
end
