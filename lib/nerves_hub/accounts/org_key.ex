defmodule NervesHub.Accounts.OrgKey do
  use Ecto.Schema

  import Ecto.Changeset

  alias __MODULE__
  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.User
  alias NervesHub.Firmwares.Firmware

  @type t :: %__MODULE__{}

  @required_params [:org_id, :created_by_id, :name, :key]
  @optional_params [:scheme]

  @schemes [:ed25519, :secure_boot_v2_rsa, :x509_certificate]

  schema "org_keys" do
    belongs_to(:org, Org)
    belongs_to(:created_by, User)
    has_many(:firmwares, Firmware)

    field(:name, :string)
    field(:key, :string)

    # Which signature scheme `key` belongs to. `ed25519` is an fwup signing key;
    # `secure_boot_v2_rsa` is a PEM RSA-3072 public key used to verify ESP-IDF
    # Secure Boot v2 signature blocks; `x509_certificate` is a PEM certificate
    # used as the trust anchor for RAUC's CMS signatures. The formats are
    # unrelated, so every consumer filters by scheme rather than trying each key
    # against each tool.
    #
    # `x509_certificate` is the odd one out in that it holds a *certificate*
    # rather than a bare public key: CMS verification is chain verification, and
    # a public key alone cannot anchor a chain.
    field(:scheme, Ecto.Enum, values: @schemes, default: :ed25519)

    timestamps()
  end

  def changeset(%OrgKey{} = org, params) do
    org
    |> cast(params, @required_params ++ @optional_params)
    |> update_change(:name, &trim/1)
    |> validate_required(@required_params)
    |> validate_key()
    |> unique_constraint(:name, name: :org_keys_org_id_name_index)
    |> unique_constraint(:key, name: :org_keys_org_id_key_index)
  end

  def update_changeset(%OrgKey{id: _} = org_key, params) do
    # don't allow org_id to change
    org_key
    |> cast(params, (@required_params -- [:org_id]) ++ @optional_params)
    |> validate_required(@required_params)
    |> validate_key()
    |> unique_constraint(:name, name: :org_keys_org_id_name_index)
    |> unique_constraint(:key, name: :org_keys_org_id_key_index)
  end

  def delete_changeset(%OrgKey{id: _} = org_key, params) do
    org_key
    |> cast(params, @required_params ++ @optional_params)
    |> foreign_key_constraint(:firmwares,
      name: :firmwares_tenant_key_id_fkey,
      message: "Firmware exists which uses the Signing Key"
    )
  end

  @doc """
  The signature schemes a key may use.
  """
  @spec schemes() :: [:ed25519 | :secure_boot_v2_rsa, ...]
  def schemes(), do: @schemes

  # `validate_change/3` only runs when `:key` changes, and it cannot see other
  # fields — so the scheme is read from the changeset here and passed down.
  defp validate_key(changeset) do
    scheme = get_field(changeset, :scheme) || :ed25519

    validate_change(changeset, :key, fn :key, key -> key_format_check(scheme, key) end)
  end

  defp key_format_check(:ed25519, encoded_key) do
    with {:ok, pub_key} <- Base.decode64(encoded_key),
         32 <- byte_size(pub_key) do
      []
    else
      _ ->
        [key: "invalid key, please check this is a valid Ed25519 public key"]
    end
  end

  # Secure Boot v2 signs with RSA-3072. Anything shorter is rejected here rather
  # than at verification time, where a too-small key would simply never match
  # and look like a signing problem instead of a registration mistake.
  defp key_format_check(:x509_certificate, pem) do
    case decode_certificate(pem) do
      {:ok, _certificate} -> []
      :error -> [key: "invalid key, expected a PEM-encoded X.509 certificate"]
    end
  end

  defp key_format_check(:secure_boot_v2_rsa, pem) do
    case decode_rsa_public_key(pem) do
      {:ok, {:RSAPublicKey, modulus, _exponent}} ->
        if bit_size_of(modulus) == 3072 do
          []
        else
          [key: "expected an RSA-3072 public key, got #{bit_size_of(modulus)} bits"]
        end

      :error ->
        [key: "invalid key, expected a PEM-encoded RSA public key"]
    end
  end

  @doc """
  Decode a `secure_boot_v2_rsa` key into an Erlang RSA public key record.
  """
  @spec decode_rsa_public_key(String.t()) :: {:ok, tuple()} | :error
  def decode_rsa_public_key(pem) when is_binary(pem) do
    case :public_key.pem_decode(pem) do
      [entry | _] ->
        case :public_key.pem_entry_decode(entry) do
          # Both "BEGIN RSA PUBLIC KEY" and the SubjectPublicKeyInfo wrapper
          # ("BEGIN PUBLIC KEY", what `openssl rsa -pubout` emits) decode to
          # this record.
          {:RSAPublicKey, _, _} = key -> {:ok, key}
          _ -> :error
        end

      _ ->
        :error
    end
  rescue
    _ -> :error
  end

  def decode_rsa_public_key(_), do: :error

  @doc """
  Decode an `x509_certificate` key into an Erlang certificate record.

  Accepts the first PEM entry, so a file holding a leaf followed by its issuers
  decodes to the leaf. RAUC verifies against a keyring rather than a single
  certificate, and a chain is written to `verify_signature/2`'s CA file in the
  order it was given.
  """
  @spec decode_certificate(String.t()) :: {:ok, tuple()} | :error
  def decode_certificate(pem) when is_binary(pem) do
    case :public_key.pem_decode(pem) do
      [{:Certificate, _der, _cipher} = entry | _] ->
        {:ok, :public_key.pem_entry_decode(entry)}

      _ ->
        :error
    end
  rescue
    _ -> :error
  end

  def decode_certificate(_), do: :error

  @doc """
  A certificate's SHA-256 fingerprint, formatted as `openssl x509
  -fingerprint -sha256` prints it.

  A PEM is 600+ bytes of base64 that reads the same for every certificate, so
  it is useless for recognising one. The fingerprint is what an operator can
  compare against the keyring built into an image.
  """
  @spec certificate_fingerprint(binary()) :: {:ok, String.t()} | :error
  def certificate_fingerprint(pem) when is_binary(pem) do
    case :public_key.pem_decode(pem) do
      [{:Certificate, der, _cipher} | _] ->
        {:ok,
         :sha256
         |> :crypto.hash(der)
         |> Base.encode16()
         |> String.replace(~r/(..)(?=.)/, "\\1:")}

      _ ->
        :error
    end
  rescue
    _ -> :error
  end

  def certificate_fingerprint(_), do: :error

  defp bit_size_of(modulus) when is_integer(modulus) do
    modulus |> :binary.encode_unsigned() |> byte_size() |> Kernel.*(8)
  end

  defp trim(string) do
    string
    |> String.split(" ", trim: true)
    |> Enum.join(" ")
  end
end
