defmodule NervesHub.Support.Utils do
  @moduledoc false

  alias NervesHub.Accounts.UserToken
  alias NervesHub.Repo
  alias NervesHub.Utils.Base62

  def create_v1_user_token!(user) do
    secret =
      <<user.name::binary, user.email::binary, DateTime.to_unix(DateTime.utc_now())::32>>

    <<initial::160>> = Plug.Crypto.KeyGenerator.generate(secret, "user-#{user.id}", length: 20)
    <<rand::30-bytes, _::binary>> = Base62.encode(initial) |> String.pad_leading(30, "0")
    crc = :erlang.crc32(rand) |> Base62.encode() |> String.pad_leading(6, "0")
    token = "nhu_#{rand}#{crc}"

    Repo.insert!(%UserToken{
      context: "api",
      note: "I love working with binary",
      old_token: token,
      user_id: user.id
    })
  end

  def nh1_key_secret_headers(auth, identifier, opts \\ []) do
    opts =
      opts
      |> Keyword.put_new(:key_digest, :sha256)
      |> Keyword.put_new(:key_iterations, 1000)
      |> Keyword.put_new(:key_length, 32)
      |> Keyword.put_new(:signed_at, System.system_time(:second))

    alg = "NH1-HMAC-#{opts[:key_digest]}-#{opts[:key_iterations]}-#{opts[:key_length]}"

    salt = """
    NH1:device-socket:shared-secret:connect

    x-nh-alg=#{alg}
    x-nh-key=#{auth.key}
    x-nh-time=#{opts[:signed_at]}
    """

    [
      {"x-nh-alg", alg},
      {"x-nh-key", auth.key},
      {"x-nh-time", to_string(opts[:signed_at])},
      {"x-nh-signature", Plug.Crypto.sign(auth.secret, salt, identifier, opts)}
    ]
  end
end
