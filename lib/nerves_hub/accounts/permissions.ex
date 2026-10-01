defmodule NervesHub.Accounts.Permissions do
  @moduledoc """
  Every permission a member of an organization can hold, and which roles hold
  them.

  A role is a set of permissions. The three built-in roles - `:admin`,
  `:manage` and `:view` - are defined here and exist in every organization.
  Each permission names the lowest built-in role that has it, and every role
  above that has it too.

  An organization can also define its own roles (`NervesHub.Accounts.OrgRole`),
  which hold whichever permissions an admin picks. Not every permission can be
  picked. Each one says how custom roles treat it:

    * `:optional` - a custom role has it only if it is picked.
    * `:always` - every custom role has it. These are the read permissions any
      member already has by being able to open the organization's pages.
    * `:never` - only the built-in admin role has it. These manage the
      organization's members, roles and the organization itself, and anyone
      holding one could use it to give themselves the rest.
  """

  alias NervesHub.Accounts.OrgRole

  @type permission() :: atom()
  @type built_in_role() :: :admin | :manage | :view
  @type custom_roles() :: :always | :optional | :never

  @type t() :: %{
          name: permission(),
          group: String.t(),
          description: String.t(),
          role: built_in_role(),
          custom_roles: custom_roles()
        }

  @built_in_roles [:admin, :manage, :view]

  @catalog [
    {"Organization",
     [
       {:"organization:update", :admin, :never, "Change the organization's settings"},
       {:"organization:delete", :admin, :never, "Delete the organization"}
     ]},
    {"Members",
     [
       {:"org_user:invite", :admin, :never, "Invite people to the organization"},
       {:"org_user:invite:resend", :admin, :never, "Resend invites and copy invite links"},
       {:"org_user:invite:rescind", :admin, :never, "Rescind invites"},
       {:"org_user:update", :admin, :never, "Change a member's role"},
       {:"org_user:delete", :admin, :never, "Remove members"}
     ]},
    {"Roles",
     [
       {:"org_role:create", :admin, :never, "Create custom roles"},
       {:"org_role:update", :admin, :never, "Edit custom roles"},
       {:"org_role:delete", :admin, :never, "Delete custom roles"}
     ]},
    {"Certificate authorities",
     [
       {:"certificate_authority:create", :manage, :optional, "Add certificate authorities"},
       {:"certificate_authority:update", :manage, :optional, "Edit certificate authorities"},
       {:"certificate_authority:delete", :manage, :optional, "Delete certificate authorities"}
     ]},
    {"Signing keys",
     [
       {:"signing_key:create", :manage, :optional, "Add firmware signing keys"},
       {:"signing_key:delete", :manage, :optional, "Delete firmware signing keys"}
     ]},
    # Registering a key nobody has proven is a privileged act: it decides which
    # organisation that key answers for, and a key belonging to someone else
    # would place their machine on this organisation's network.
    {"Network identities",
     [
       {:"network_identity:create", :manage, :optional, "Register network identities"},
       {:"network_identity:delete", :manage, :optional, "Delete network identities"}
     ]},
    {"Products",
     [
       {:"product:create", :manage, :optional, "Create products"},
       {:"product:update", :manage, :optional, "Change product settings"},
       {:"product:delete", :manage, :optional, "Delete products"},
       {:"product:notifications:dismiss", :manage, :optional, "Dismiss product notifications"},
       {:"error_group:update", :manage, :optional, "Resolve and reopen reported errors"}
     ]},
    {"Devices",
     [
       {:"device:view", :view, :always, "View devices and stream their events"},
       {:"device:create", :manage, :optional, "Add devices"},
       {:"device:update", :manage, :optional, "Edit devices and their settings"},
       {:"device:tags", :manage, :optional, "Change device tags"},
       {:"device:delete", :manage, :optional, "Delete devices"},
       {:"device:restore", :manage, :optional, "Restore deleted devices"},
       {:"device:destroy", :manage, :optional, "Permanently destroy deleted devices"},
       {:"device:console", :manage, :optional, "Open a device's remote console"},
       {:"device:extensions:local_shell", :manage, :optional, "Open a device's local shell"},
       {:"device:identify", :manage, :optional, "Ask a device to identify itself"},
       {:"device:reboot", :manage, :optional, "Reboot devices"},
       {:"device:reconnect", :manage, :optional, "Reconnect devices"},
       {:"device:push-update", :manage, :optional, "Push firmware to a device"},
       {:"device:toggle-updates", :manage, :optional, "Turn a device's updates on or off"},
       {:"device:clear-penalty-box", :manage, :optional, "Clear a device's penalty box"},
       {:"device:set-deployment-group", :manage, :optional, "Move a device into a deployment group"}
     ]},
    {"Firmware and archives",
     [
       {:"firmware:upload", :manage, :optional, "Upload firmware"},
       {:"firmware:download", :manage, :optional, "Download firmware"},
       {:"firmware:delete", :manage, :optional, "Delete firmware"},
       {:"archive:upload", :manage, :optional, "Upload archives"},
       {:"archive:delete", :manage, :optional, "Delete archives"}
     ]},
    {"Deployment groups",
     [
       {:"deployment_group:create", :manage, :optional, "Create deployment groups"},
       {:"deployment_group:update", :manage, :optional, "Edit deployment groups and their releases"},
       {:"deployment_group:toggle", :manage, :optional, "Turn deployment groups on or off"},
       {:"deployment_group:toggle_delta_updates", :manage, :optional, "Turn delta updates on or off"},
       {:"deployment_group:delete", :manage, :optional, "Delete deployment groups"}
     ]},
    {"Support scripts",
     [
       {:"support_script:run", :view, :optional, "Run support scripts on devices"},
       {:"support_script:create", :manage, :optional, "Create support scripts"},
       {:"support_script:update", :manage, :optional, "Edit support scripts"},
       {:"support_script:delete", :manage, :optional, "Delete support scripts"}
     ]}
  ]

  @permissions for {group, permissions} <- @catalog,
                   {name, role, custom_roles, description} <- permissions,
                   do: %{name: name, group: group, description: description, role: role, custom_roles: custom_roles}

  @grouped for {group, _} <- @catalog, do: {group, Enum.filter(@permissions, &(&1.group == group))}

  @by_name Map.new(@permissions, &{&1.name, &1})

  @role_rank %{view: 0, manage: 1, admin: 2}

  @built_in_permissions Map.new(@built_in_roles, fn role ->
                          granted =
                            for permission <- @permissions,
                                @role_rank[permission.role] <= @role_rank[role],
                                into: MapSet.new(),
                                do: permission.name

                          {role, granted}
                        end)

  @custom_role_baseline for %{custom_roles: :always, name: name} <- @permissions, into: MapSet.new(), do: name

  # What a custom role limited to tagged devices can be given: things done to
  # one device at a time. Everything else acts on something its members can't
  # see all of - a product, a deployment group, the org's firmware - and those
  # pages are closed to them.
  @device_permissions ~w(
    device:update
    device:tags
    device:delete
    device:restore
    device:destroy
    device:console
    device:extensions:local_shell
    device:identify
    device:reboot
    device:reconnect
    device:push-update
    device:toggle-updates
    device:clear-penalty-box
    device:set-deployment-group
    support_script:run
  )

  # Custom roles store their permissions as strings. Only these are read back,
  # so a permission that is renamed, removed, or made admin-only after a role
  # was saved stops granting anything rather than failing to load.
  @custom_role_optional for %{custom_roles: :optional, name: name} <- @permissions,
                            into: %{},
                            do: {Atom.to_string(name), name}

  @doc """
  The built-in roles, highest first.
  """
  @spec built_in_roles() :: [built_in_role(), ...]
  def built_in_roles(), do: @built_in_roles

  @doc """
  Every permission, in display order.
  """
  @spec all() :: [t()]
  def all(), do: @permissions

  @doc """
  Every permission grouped for display, as `{group, permissions}` pairs.
  """
  @spec grouped() :: [{String.t(), [t()]}]
  def grouped(), do: @grouped

  @doc """
  Whether `permission` is one this module defines.
  """
  @spec known?(atom()) :: boolean()
  def known?(permission), do: Map.has_key?(@by_name, permission)

  @doc """
  The names of the permissions an admin can pick for a custom role, as they are
  stored on `NervesHub.Accounts.OrgRole`.
  """
  @spec custom_role_options() :: [String.t()]
  def custom_role_options(), do: Map.keys(@custom_role_optional)

  @doc """
  The permissions a custom role limited to tagged devices can be given, as they
  are stored on `NervesHub.Accounts.OrgRole`.
  """
  @spec device_permissions() :: [String.t()]
  def device_permissions(), do: @device_permissions

  @doc """
  The permissions a role grants.

  Takes a built-in role or a custom `NervesHub.Accounts.OrgRole`. A custom role
  grants the permissions every custom role has plus the ones picked for it.
  Anything else, including `nil`, grants nothing.
  """
  @spec for_role(built_in_role() | OrgRole.t() | nil) :: MapSet.t(permission())
  def for_role(role) when role in @built_in_roles, do: Map.fetch!(@built_in_permissions, role)

  def for_role(%OrgRole{permissions: permissions}) do
    for permission <- permissions,
        {:ok, name} <- [Map.fetch(@custom_role_optional, permission)],
        into: @custom_role_baseline,
        do: name
  end

  def for_role(_role), do: MapSet.new()

  @doc """
  Whether `permissions` includes `permission`.

  Raises `ArgumentError` for a permission this module doesn't define, so a
  misspelt check fails loudly instead of quietly denying everyone.
  """
  @spec granted?(MapSet.t(permission()), permission()) :: boolean()
  def granted?(permissions, permission) do
    known?(permission) || raise ArgumentError, "unknown permission #{inspect(permission)}"

    MapSet.member?(permissions, permission)
  end
end
