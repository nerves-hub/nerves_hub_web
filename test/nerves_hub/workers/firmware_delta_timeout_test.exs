defmodule NervesHub.Workers.FirmwareDeltaTimeoutTest do
  use NervesHub.DataCase, async: true
  use Mimic

  alias NervesHub.Firmwares
  alias NervesHub.Workers.FirmwareDeltaTimeout

  describe "perform/1" do
    test "returns :ok when no pending deltas exist" do
      job = %Oban.Job{id: Ecto.UUID.generate(), attempt: 1, args: %{}}
      assert :ok = FirmwareDeltaTimeout.perform(job)
    end

    test "calls time_out_firmware_delta_generations and returns :ok" do
      test_pid = self()

      stub(Firmwares, :time_out_firmware_delta_generations, fn age, unit ->
        send(test_pid, {:timed_out, age, unit})
        []
      end)

      job = %Oban.Job{id: Ecto.UUID.generate(), attempt: 1, args: %{}}
      assert :ok = FirmwareDeltaTimeout.perform(job)

      assert_receive {:timed_out, 960, :second}, 500
    end
  end
end
