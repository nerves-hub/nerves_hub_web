defmodule NervesHub.Repo.Migrations.GrantReleaseManageToCustomRoles do
  use Ecto.Migration

  # Creating, editing and approving releases moved from `deployment_group:update`
  # to `deployment_group:release:manage`, so a custom role that could do them
  # before keeps doing them. Permissions are stored sorted, as `OrgRole` saves
  # them.
  #
  # Creating a group, which starts with a release, needs the new permission
  # too, but a role with only `deployment_group:create` isn't given it: that
  # would let it approve steps and send releases on every group, which it
  # couldn't before. Until an admin adds it, such a role can't create groups.
  #
  # A node still on the old code during a rolling deploy has no checkbox for
  # the new permission, so a role saved there loses it. The statement in `up/0`
  # can be run again once every node is on the new code; it only adds the
  # permission where it's missing.
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
