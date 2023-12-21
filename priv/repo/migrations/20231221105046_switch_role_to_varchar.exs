defmodule NervesHub.Repo.Migrations.SwitchRoleToVarchar do
  use Ecto.Migration

  def change do
    execute "ALTER TABLE org_users ALTER COLUMN role TYPE varchar;"
    execute "ALTER TABLE product_users ALTER COLUMN role TYPE varchar;"

    execute "UPDATE org_users SET role = 'admin' WHERE role = 'delete';"
    execute "UPDATE org_users SET role = 'manage' WHERE role = 'write';"
    execute "UPDATE org_users SET role = 'view' WHERE role = 'read';"

    execute "UPDATE product_users SET role = 'admin' WHERE role = 'delete';"
    execute "UPDATE product_users SET role = 'manage' WHERE role = 'write';"
    execute "UPDATE product_users SET role = 'view' WHERE role = 'read';"

    execute "DROP TYPE role;"
  end
end
