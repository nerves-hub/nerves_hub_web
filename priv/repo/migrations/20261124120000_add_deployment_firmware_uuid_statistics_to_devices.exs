defmodule NervesHub.Repo.Migrations.AddDeploymentFirmwareUuidStatisticsToDevices do
  use Ecto.Migration

  # The deployment group pages count a product's devices by group and by the
  # firmware each runs. Postgres keeps no statistics on
  # `firmware_metadata->>'uuid'` and takes it to be independent of
  # `deployment_id`, so it guesses hundreds of thousands of groups where there
  # are a few hundred, sorts every device to group them, and spills the sort to
  # disk. Telling it how many (group, firmware) pairs there are lets it hash
  # them instead.
  #
  # Statistics change only the planner's estimates, never what a query
  # returns, and nothing maintains them on writes: autovacuum's ANALYZE of
  # `devices` refreshes them. The ANALYZE here fills them in straight away
  # rather than at the next autovacuum. It reads a sample of the table and
  # doesn't block reads or writes.
  def up() do
    execute("""
    CREATE STATISTICS IF NOT EXISTS devices_deployment_fw_uuid_stats (ndistinct)
      ON deployment_id, (firmware_metadata->>'uuid') FROM devices
    """)

    execute("ANALYZE devices")
  end

  def down() do
    execute("DROP STATISTICS IF EXISTS devices_deployment_fw_uuid_stats")
  end
end
