defmodule NervesHub.Accounts.Scope do
  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.OrgRole
  alias NervesHub.Accounts.Permissions
  alias NervesHub.Accounts.User
  alias NervesHub.Products.Product

  defstruct org: nil, permissions: MapSet.new(), product: nil, role: nil, user: nil

  @type t :: %__MODULE__{
          org: Org.t() | nil,
          permissions: MapSet.t(Permissions.permission()),
          product: Product.t() | nil,
          role: Permissions.built_in_role() | OrgRole.t() | nil,
          user: User.t() | nil
        }

  def for_user(%User{} = user) do
    %__MODULE__{user: user}
  end

  def for_user(nil), do: nil

  def put_org(%__MODULE__{} = scope, %Org{} = org) do
    %{scope | org: org}
  end

  @doc """
  Sets the user's role in the scope's org, and the permissions it grants.

  Takes a built-in role or a custom `NervesHub.Accounts.OrgRole`, as
  `NervesHub.Accounts.OrgUser.assigned_role/1` returns them.
  """
  def put_role(%__MODULE__{} = scope, role) when is_atom(role) or is_struct(role, OrgRole) do
    %{scope | role: role, permissions: Permissions.for_role(role)}
  end

  def put_product(%__MODULE__{} = scope, %Product{} = product) do
    %{scope | product: product}
  end
end
