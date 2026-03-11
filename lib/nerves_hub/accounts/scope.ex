defmodule NervesHub.Accounts.Scope do
  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.User
  alias NervesHub.Products.Product

  defstruct org: nil, product: nil, role: nil, user: nil

  @type t :: %__MODULE__{
          org: Org.t() | nil,
          product: Product.t() | nil,
          role: atom() | nil,
          user: User.t() | nil
        }

  def for_user(%User{} = user) do
    %__MODULE__{user: user}
  end

  def for_user(nil), do: nil

  def put_org(%__MODULE__{} = scope, %Org{} = org) do
    %{scope | org: org}
  end

  def put_role(%__MODULE__{} = scope, role) when is_atom(role) do
    %{scope | role: role}
  end

  def put_product(%__MODULE__{} = scope, %Product{} = product) do
    %{scope | product: product}
  end
end
