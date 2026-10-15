defmodule NervesHub.Types.Encrypted do
  @moduledoc """
  An Ecto type for a secret NervesHub holds on someone else's behalf, such as
  a Slack bot token: a string that NervesHub has to send back out, so it
  cannot be hashed, and that would let whoever read it act as that someone.

  The value is encrypted with AES-256-GCM before it reaches the database, so
  a leaked dump or backup carries no usable token without the key, which
  lives outside the database. GCM authenticates as well as encrypts: a stored
  value that was altered fails to load rather than decrypting to something
  else.

  Stored as `<<version, iv::12 bytes, tag::16 bytes, ciphertext>>`. The
  version byte names the key format, which leaves room to rotate keys later
  without guessing what an old row was written with.

  The key is 32 bytes, configured as
  `config :nerves_hub, NervesHub.Types.Encrypted, key: ...`, which
  `config/runtime.exs` sets from `SECRETS_ENCRYPTION_KEY`.
  """
  use Ecto.Type

  @version 1

  # Binds a ciphertext to this purpose, so bytes encrypted under the same key
  # for anything else will not load as one of these.
  @aad "NervesHub.Types.Encrypted.v1"

  @impl Ecto.Type
  def type(), do: :binary

  @impl Ecto.Type
  def cast(value) when is_binary(value), do: {:ok, value}
  def cast(_value), do: :error

  @impl Ecto.Type
  def dump(value) when is_binary(value), do: {:ok, encrypt(value)}
  def dump(_value), do: :error

  @impl Ecto.Type
  def load(<<@version, iv::binary-12, tag::binary-16, ciphertext::binary>>) do
    case :crypto.crypto_one_time_aead(:aes_256_gcm, key(), iv, ciphertext, @aad, tag, false) do
      :error -> :error
      plaintext -> {:ok, plaintext}
    end
  end

  def load(_value), do: :error

  defp encrypt(plaintext) do
    iv = :crypto.strong_rand_bytes(12)
    {ciphertext, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key(), iv, plaintext, @aad, true)

    <<@version, iv::binary, tag::binary, ciphertext::binary>>
  end

  defp key() do
    case Application.get_env(:nerves_hub, __MODULE__, [])[:key] do
      <<_::binary-32>> = key ->
        key

      _missing_or_wrong_size ->
        raise ArgumentError,
              "NervesHub.Types.Encrypted needs a 32 byte key; set SECRETS_ENCRYPTION_KEY to 32 random bytes, base64 encoded"
    end
  end
end
