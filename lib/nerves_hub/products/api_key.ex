defmodule NervesHub.Products.ApiKey do
  @moduledoc """
  A credential for automation, such as a CI pipeline, that works on one product
  without a person's account behind it.

  A user API token acts with everything its user can reach, in every
  organization they belong to, and stops working when they leave. An API key
  belongs to a product instead. It reaches that product's API routes and
  nothing else, it holds a role of its own, and it outlives whoever created it.

  Like a member (`NervesHub.Accounts.OrgUser`), a key holds either a built-in
  role or one of the organization's custom roles, never both, and the role
  decides what it may do through `NervesHub.Accounts.Permissions`. The built-in
  admin role is not offered: what it adds over manage is running the
  organization, which no key reaches.

  Only a hash of the key is stored. The key itself is handed back once, when it
  is created, in the same shape as a user API token (see
  `NervesHub.Accounts.UserToken.build_hashed_token/3`): a prefix, then Base62 of
  32 random bytes followed by their CRC32. The prefix tells a request which kind
  of credential it is carrying and lets secret scanners recognize a leaked key.
  The CRC turns away a mistyped or truncated key before it costs a database
  lookup.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.OrgRole
  alias NervesHub.Accounts.User
  alias NervesHub.Products.Product
  alias NervesHub.Utils.Base62

  @type t :: %__MODULE__{}
  @type built_in_role :: :view | :manage

  @prefix "nhpk_"
  @built_in_roles [:view, :manage]

  @rand_size 32
  @hash_algorithm :sha512

  # Base62 of 36 bytes is at most 49 characters. Anything much longer can't be a
  # key, and is refused before it reaches the decoder.
  @max_encoded_size 64

  schema "product_api_keys" do
    belongs_to(:product, Product)
    belongs_to(:org, Org)
    belongs_to(:created_by, User)

    # A key holds a built-in `role` or a custom `org_role`, never both.
    belongs_to(:org_role, OrgRole, where: [deleted_at: nil])
    field(:role, Ecto.Enum, values: @built_in_roles)

    field(:name, :string)
    field(:token_hash, :binary, redact: true)

    field(:last_used_at, :utc_datetime)
    field(:deactivated_at, :utc_datetime)

    timestamps()
  end

  @doc """
  The built-in roles a key can be given.

  Admin is not among them; see the moduledoc.
  """
  @spec built_in_roles() :: [built_in_role(), ...]
  def built_in_roles(), do: @built_in_roles

  @doc """
  The role a key holds: a built-in role, or the organization's custom `OrgRole`.

  A custom role must be preloaded. One that has since been deleted comes back
  as `nil`, which grants nothing.
  """
  @spec assigned_role(t()) :: built_in_role() | OrgRole.t() | nil
  def assigned_role(%__MODULE__{org_role_id: nil, role: role}), do: role

  def assigned_role(%__MODULE__{org_role: %Ecto.Association.NotLoaded{}}) do
    raise ArgumentError, "the key's custom role must be preloaded to know what it grants"
  end

  def assigned_role(%__MODULE__{org_role: org_role}), do: org_role

  @doc """
  Whether a token claims to be an API key, going by its prefix alone.
  """
  @spec token?(String.t()) :: boolean()
  def token?(@prefix <> _), do: true
  def token?(_token), do: false

  @doc """
  A changeset for a new key, along with the key itself.

  This is the only place the key exists: the changeset carries its hash. The
  product decides the organization, so a role from any other one is refused.
  """
  @spec create_changeset(Product.t(), User.t(), map()) :: {String.t(), Ecto.Changeset.t()}
  def create_changeset(%Product{} = product, %User{} = created_by, attrs) do
    secret = random_secret()
    token = @prefix <> Base62.encode(<<secret::binary, :erlang.crc32(secret)::32>>)

    changeset =
      %__MODULE__{
        product_id: product.id,
        org_id: product.org_id,
        created_by_id: created_by.id,
        token_hash: hash(secret)
      }
      |> cast(attrs, [:name, :role, :org_role_id])
      |> update_change(:name, &String.trim/1)
      |> validate_required([:name])
      |> validate_length(:name, max: 255)
      |> OrgRole.validate_assignment()
      |> unique_constraint(:token_hash)
      |> foreign_key_constraint(:product_id)

    {token, changeset}
  end

  @spec deactivate_changeset(t()) :: Ecto.Changeset.t()
  def deactivate_changeset(%__MODULE__{} = api_key) do
    change(api_key, deactivated_at: DateTime.utc_now(:second))
  end

  @doc """
  The hash a key is stored under, or `:error` if the string isn't a well formed
  key.
  """
  @spec hash_token(String.t()) :: {:ok, binary()} | :error
  def hash_token(@prefix <> encoded) when byte_size(encoded) <= @max_encoded_size do
    with {:ok, <<secret::binary-size(@rand_size), crc::32>>} <- Base62.decode(encoded),
         true <- :erlang.crc32(secret) == crc do
      {:ok, hash(secret)}
    else
      _ -> :error
    end
  end

  def hash_token(_token), do: :error

  defp hash(secret), do: :crypto.hash(@hash_algorithm, secret)

  defp random_secret() do
    case :crypto.strong_rand_bytes(@rand_size) do
      # Base62 works on the bytes as one integer, so a leading zero byte would
      # vanish on the way through and the key would decode short.
      <<0, _::binary>> -> random_secret()
      secret -> secret
    end
  end
end
