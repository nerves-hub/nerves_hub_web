defmodule Beamware.Accounts do
  alias Ecto.Changeset
  alias Beamware.Accounts.{Tenant, User}
  alias Beamware.Repo

  @doc """
  Create a tenant. Expects `params` to contain fields for both the user and tenant.
  """
  @spec create_tenant(map)
  :: {:ok, Tenant.t()}
  |  {:error, Changeset.t()}
  def create_tenant(params) do
    types = %{
      name: :string,
      tenant_name: :string,
      email: :string,
      password: :string
    }

    changeset =
      {%{}, types}
      |> Changeset.cast(params, Map.keys(types))
      |> Changeset.validate_required([
        :name,
        :tenant_name,
        :email,
        :password
      ])

    # Ensure Phoenix.Form shows errors
    changeset = %{changeset | action: :insert}

    changeset
    |> case do
      %Changeset{valid?: false} = changeset ->
        {:error, changeset}

      %Changeset{valid?: true} = changeset ->
        do_create_tenant(changeset)
    end
  end

  @spec do_create_tenant(Changeset.t())
  :: {:ok, Tenant.t()}
  |  {:error, Changeset.t()}
  defp do_create_tenant(tenant_user_changeset) do
    field = fn(field_name) -> Changeset.get_field(tenant_user_changeset, field_name) end

    tenant_params = %{
      name: field.(:tenant_name)
    }

    user_params = %{
      name: field.(:name),
      email: field.(:email),
      password: field.(:password)
    }

    Repo.transaction(fn() ->
      with {:ok, tenant} <- tenant_params |> Tenant.creation_changeset() |> Repo.insert(),
           {:ok, _user} <- create_user(tenant, user_params)
      do
        tenant
      else
        {:error, changeset} ->
          # Merge errors into original changeset
          changeset.errors
          |> Enum.reduce(tenant_user_changeset, fn({key, {message, data}}, changeset) ->
            Changeset.add_error(changeset, key, message, data)
          end)
          |> Repo.rollback()
      end
    end)
  end

  @spec create_user(Tenant.t(), map)
  :: {:ok, User.t()}
  |  {:error, Changeset.t()}
  def create_user(%Tenant{} = tenant, params) do
    tenant
    |> Ecto.build_assoc(:users)
    |> User.creation_changeset(params)
    |> Repo.insert()
  end
end
