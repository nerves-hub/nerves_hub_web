defmodule NervesHubCore.CertificateAuthority do
  def start_pool() do
    pool = :nerves_hub_ca
    pool_opts = [timeout: 150_000, max_connections: 10]
    :ok = :hackney_pool.start_pool(pool, pool_opts)
  end

  def create_device_certificate(serial) do
    body = Jason.encode!(%{serial: serial})
    url = url("/create_device_certificate")

    :hackney.request(:post, url, headers(), body, opts())
    |> resp()
  end

  def create_user_certificate(username) do
    body = Jason.encode!(%{username: username})
    url = url("/create_user_certificate")

    :hackney.request(:post, url, headers(), body, opts())
    |> resp()
  end

  def sign_user_csr(csr) do
    body = Jason.encode!(%{csr: csr})
    url = url("/sign_user_csr")

    :hackney.request(:post, url, headers(), body, opts())
    |> resp()
  end

  def get_certificate_info(cert) do
    body = Jason.encode!(%{certificate: cert})
    url = url("/certinfo")

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
    Application.get_env(:nerves_hub_core, __MODULE__, [])
  end
end
