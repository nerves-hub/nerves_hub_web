defmodule NervesHub.Repo.Migrations.AllowUnsignedAtomvmFirmwareSetting do
  @moduledoc """
  Let a product decide whether it accepts unsigned AtomVM firmware.

  Packbeam has no signature of its own, so NervesHub defines one and `nh-avm`
  produces it. Nothing else in the AtomVM toolchain does, which is why this is
  a setting rather than a rule: a product built with other tooling has no way
  to sign yet.

  Defaults to false, matching `allow_unsigned_esp_idf_firmware`. Turning a
  format on and getting signed-only is the safer of the two surprises.
  """

  use Ecto.Migration

  def change() do
    alter table(:products) do
      add(:allow_unsigned_atomvm_firmware, :boolean, null: false, default: false)
    end
  end
end
