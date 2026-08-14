defmodule NervesHub.Workers.ExpireInflightUpdatesTest do
  use NervesHub.DataCase, async: true

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
end
