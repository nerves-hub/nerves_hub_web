defmodule NervesHubWebCore.CertificateAuthority do
  def start_pool() do
    pool = :nerves_hub_ca
    pool_opts = [timeout: 150_000, max_connections: 10]
    :ok = :hackney_pool.start_pool(pool, pool_opts)
  end

  def create_device_certificate(serial) do
    subject = "/O=NervesHub/CN=" <> serial
    key = X509.PrivateKey.new_ec(:secp256r1)
    key_pem = X509.PrivateKey.to_pem(key)

    csr =
      X509.CSR.new(key, subject)
      |> X509.CSR.to_pem()
      |> Base.encode64()

    case sign_device_csr(csr) do
      {:ok, resp} -> {:ok, Map.put(resp, "key", key_pem)}
      error -> error
    end
  end

  def create_user_certificate(username) do
    subject = "/O=NervesHub/CN=" <> username
    key = X509.PrivateKey.new_ec(:secp256r1)
    key_pem = X509.PrivateKey.to_pem(key)

    csr =
      X509.CSR.new(key, subject)
      |> X509.CSR.to_pem()
      |> Base.encode64()

    case sign_user_csr(csr) do
      {:ok, resp} -> {:ok, Map.put(resp, "key", key_pem)}
      error -> error
    end
  end

  def sign_user_csr(csr) do
    body = Jason.encode!(%{csr: csr})
    url = url("/sign_user_csr")

    :hackney.request(:post, url, headers(), body, opts())
    |> resp()
  end

  def sign_device_csr(csr) do
    body = Jason.encode!(%{csr: csr})
    url = url("/sign_device_csr")

    :hackney.request(:post, url, headers(), body, opts())
    |> resp()
  end

  def resp({:ok, 200, _headers, client_ref}) do
    case :hackney.body(client_ref) do
      {:ok, body} ->
        Jason.decode(body)

      error ->
        error
    end
  after
    :hackney.close(client_ref)
  end

  def resp(resp) do
    {:error, resp}
  end

  def url(path) do
    endpoint() <> path
  end

  def endpoint do
    config = config()
    host = config[:host]
    port = config[:port]
    "https://#{host}:#{port}"
  end

  def headers do
    [{"Content-Type", "application/json"}]
  end

  def opts do
    [
      pool: :nerves_hub_ca,
      ssl_options: Keyword.get(config(), :ssl, [])
    ]
  end

  def config do
    Application.get_env(:nerves_hub_web_core, __MODULE__, [])
  end
end
