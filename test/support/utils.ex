defmodule NervesHub.Support.Utils do
  @moduledoc false

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
