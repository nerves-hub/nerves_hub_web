defmodule NervesHub.Accounts.PermissionsTest do
  use ExUnit.Case, async: true

  alias NervesHub.Accounts.OrgRole
  alias NervesHub.Accounts.Permissions

  # The lowest built-in role that had each permission when they were
  # hardcoded, plus the role permissions added alongside custom roles. Moving
  # the checks into a catalog must not change what a built-in role can do.
  # (`network_identity:view` was dropped then too: nothing ever checked it.)
  # When the API moved to permissions, certificate authorities moved from admin
  # to manage, and `firmware:download` was added at manage for both the API and
  # the dashboard.
  @built_in_minimums %{
    "archive:delete": :manage,
    "archive:upload": :manage,
    "certificate_authority:create": :manage,
    "certificate_authority:delete": :manage,
    "certificate_authority:update": :manage,
    "deployment_group:create": :manage,
    "deployment_group:delete": :manage,
    "deployment_group:toggle": :manage,
    "deployment_group:toggle_delta_updates": :manage,
    "deployment_group:update": :manage,
    "device:clear-penalty-box": :manage,
    "device:console": :manage,
    "device:create": :manage,
    "device:delete": :manage,
    "device:destroy": :manage,
    "device:extensions:local_shell": :manage,
    "device:identify": :manage,
    "device:push-update": :manage,
    "device:reboot": :manage,
    "device:reconnect": :manage,
    "device:restore": :manage,
    "device:set-deployment-group": :manage,
    "device:tags": :manage,
    "device:toggle-updates": :manage,
    "device:update": :manage,
    "device:view": :view,
    "error_group:update": :manage,
    "firmware:delete": :manage,
    "firmware:download": :manage,
    "firmware:upload": :manage,
    "network_identity:create": :manage,
    "network_identity:delete": :manage,
    "org_role:create": :admin,
    "org_role:delete": :admin,
    "org_role:update": :admin,
    "org_user:delete": :admin,
    "org_user:invite": :admin,
    "org_user:invite:rescind": :admin,
    "org_user:invite:resend": :admin,
    "org_user:update": :admin,
    "organization:delete": :admin,
    "organization:update": :admin,
    "product:create": :manage,
    "product:delete": :manage,
    "product:notifications:dismiss": :manage,
    "product:update": :manage,
    "signing_key:create": :manage,
    "signing_key:delete": :manage,
    "support_script:create": :manage,
    "support_script:delete": :manage,
    "support_script:run": :view,
    "support_script:update": :manage
  }

  @higher_or_equal %{admin: [:admin], manage: [:admin, :manage], view: [:admin, :manage, :view]}

  describe "built-in roles" do
    test "every permission is in the catalog once" do
      names = Enum.map(Permissions.all(), & &1.name)

      assert Enum.sort(names) == Enum.sort(Map.keys(@built_in_minimums))
    end

    test "grant exactly what they did when the checks were hardcoded" do
      for {permission, minimum} <- @built_in_minimums, role <- Permissions.built_in_roles() do
        expected = role in @higher_or_equal[minimum]

        assert MapSet.member?(Permissions.for_role(role), permission) == expected,
               "expected #{role} #{if expected, do: "to", else: "not to"} have #{permission}"
      end
    end
  end

  describe "custom roles" do
    test "grant what was picked, plus what every member has" do
      role = %OrgRole{permissions: ["device:reboot", "firmware:upload"]}

      assert Permissions.for_role(role) ==
               MapSet.new([:"device:reboot", :"firmware:upload", :"device:view"])
    end

    test "never grant an admin-only permission, even one saved on the role" do
      role = %OrgRole{permissions: ["org_user:update", "org_role:create", "organization:delete"]}

      assert Permissions.for_role(role) == MapSet.new([:"device:view"])
    end

    test "ignore permissions that don't exist" do
      role = %OrgRole{permissions: ["device:reboot", "device:teleport"]}

      assert MapSet.member?(Permissions.for_role(role), :"device:reboot")
      refute Enum.any?(Permissions.for_role(role), &(&1 == :"device:teleport"))
    end

    test "can't be given the admin-only permissions" do
      options = Permissions.custom_role_options()

      for %{name: name, custom_roles: :never} <- Permissions.all() do
        refute Atom.to_string(name) in options
      end

      refute "device:view" in options
      assert "device:console" in options
      assert "certificate_authority:create" in options
    end
  end

  test "no role grants nothing" do
    assert Permissions.for_role(nil) == MapSet.new()
  end

  test "granted?/2 refuses to answer for a permission that doesn't exist" do
    assert_raise ArgumentError, ~r/unknown permission/, fn ->
      Permissions.granted?(Permissions.for_role(:admin), :"device:teleport")
    end
  end
end
