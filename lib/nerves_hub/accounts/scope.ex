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

  @doc """
  Whether the user sees only some of the org's devices: their custom role is
  limited to tagged devices, or they have no role that could say otherwise.

  Pages and endpoints built from all of a product's devices, like Insights or a
  deployment group, are closed to them. Which devices they do see is decided
  in the database; see `NervesHub.Devices.Visibility`.
  """
  @spec devices_limited?(t()) :: boolean()
  def devices_limited?(%__MODULE__{role: role}) when role in [:admin, :manage, :view], do: false
  def devices_limited?(%__MODULE__{role: %OrgRole{} = role}), do: OrgRole.limited_to_tags?(role)
  def devices_limited?(%__MODULE__{}), do: true
end
