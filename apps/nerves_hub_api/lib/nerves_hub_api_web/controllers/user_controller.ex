defmodule NervesHubAPIWeb.UserController do
  use NervesHubAPIWeb, :controller

  alias NervesHubWebCore.Accounts
  alias NervesHubWebCore.{CertificateAuthority, Certificate}

  action_fallback(NervesHubAPIWeb.FallbackController)

  def me(%{assigns: %{user: user}} = conn, _params) do
    render(conn, "show.json", user: user)
  end

  def register(conn, params) do
    params =
      params
      |> whitelist([:username, :email, :password])

    with {:ok, user} <- Accounts.create_user(params) do
      render(conn, "show.json", user: user)
    end
  end

  def auth(conn, %{"email" => email, "password" => password}) do
    with {:ok, user} <- Accounts.authenticate(email, password) do
      render(conn, "show.json", user: user)
    end
  end

  def sign(conn, %{
        "csr" => csr,
        "email" => email,
        "password" => password,
        "description" => description
      }) do
    with {:ok, user} <- Accounts.authenticate(email, password),
         {:ok, %{"cert" => cert_pem}} <- CertificateAuthority.sign_user_csr(csr),
         {:ok, cert} <- X509.Certificate.from_pem(cert_pem),
         serial <- Certificate.get_serial_number(cert),
         aki <- Certificate.get_aki(cert),
         ski <- Certificate.get_ski(cert),
         {not_before, not_after} <- Certificate.get_validity(cert),
         params <- %{
           description: description,
           serial: serial,
           aki: aki,
           ski: ski,
           not_before: not_before,
           not_after: not_after
         },
         {:ok, _db_cert} <- Accounts.create_user_certificate(user, params) do
      render(conn, "cert.json", cert: cert_pem)
    end
  end
end
