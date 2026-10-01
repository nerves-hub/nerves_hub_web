defmodule NervesHub.Repo.Migrations.AddDeviceTagsToOrgRoles do
  use Ecto.Migration

  def change() do
    alter table(:org_roles) do
      # No tags means the role sees every device in the org.
      add(:device_tags, {:array, :string}, null: false, default: [])
      add(:device_tag_operator, :string, null: false, default: "and")
    end
  end
end
