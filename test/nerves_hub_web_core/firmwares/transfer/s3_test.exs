defmodule NervesHubWebCore.Firmware.Transfer.S3Test do
  use NervesHubWebCore.DataCase, async: true
  alias NervesHubWebCore.Workers.FirmwaresTransferS3Ingress, as: Ingress

  @fixture Path.expand("../../../../test/fixtures/s3_access_log.txt", __DIR__)

  test "can parse transfer records to firmware_tranfer params" do
    expected = %{
      org_id: 1,
      firmware_uuid: "d123bf9c-3d4d-5ae9-615e-6b5ce1d2845c",
      remote_ip: "192.0.2.3",
      bytes_sent: 300_000,
      bytes_total: 32_184_752,
      timestamp: Ingress.decode_time("[08/Feb/2019:00:10:44 +0000]")
    }

    {:ok, data} =
      File.read!(@fixture)
      |> String.split("\n")
      |> List.first()
      |> Ingress.decode_row()

    assert data == expected
  end

  test "only firmware transfer records are decoded from log" do
    data =
      File.read!(@fixture)
      |> Ingress.decode_log()

    assert length(data) == 1
  end

  test "non transfer records are skipped" do
    assert {:error, _} = Ingress.decode_row("12345")
  end
end
