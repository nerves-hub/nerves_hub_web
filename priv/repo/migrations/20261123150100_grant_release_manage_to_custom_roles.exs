defmodule NervesHub.Repo.Migrations.GrantReleaseManageToCustomRoles do
  use Ecto.Migration

  # Creating, editing and approving releases moved from `deployment_group:update`
  # to `deployment_group:release:manage`. A custom role that could do those
  # before keeps doing them. Permissions are stored sorted, as `OrgRole` saves
  # them.
  def up() do
    execute("""
    UPDATE org_roles
    SET permissions = ARRAY(
      SELECT DISTINCT p FROM unnest(permissions || ARRAY['deployment_group:release:manage']) AS p ORDER BY p
    )
    WHERE 'deployment_group:update' = ANY(permissions)
      AND NOT 'deployment_group:release:manage' = ANY(permissions)
    """)
  end

  def down() do
    execute("""
    UPDATE org_roles
    SET permissions = array_remove(permissions, 'deployment_group:release:manage')
    WHERE 'deployment_group:release:manage' = ANY(permissions)
    """)
  end
end
