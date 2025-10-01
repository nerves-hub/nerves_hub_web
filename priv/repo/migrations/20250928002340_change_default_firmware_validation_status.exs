defmodule NervesHub.Repo.Migrations.ChangeDefaultFirmwareValidationStatus do
  use Ecto.Migration

  def up() do
    execute(
      "UPDATE devices SET firmware_validation_status = 'unknown' WHERE firmware_validation_status = 'not_supported'"
    )
  end

  def down() do
    # noop
  end
end
