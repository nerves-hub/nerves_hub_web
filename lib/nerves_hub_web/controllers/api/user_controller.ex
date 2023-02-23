defmodule NervesHubWeb.API.UserController do
  use NervesHubWeb, :api_controller

  alias NervesHub.Accounts
  alias NervesHub.{CertificateAuthority, Certificate}

  plug(NervesHub.Plugs.AllowUninvitedSignups when action == :register)

  action_fallback(NervesHubWeb.API.FallbackController)

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

  def auth(conn, %{"password" => password} = opts) do
    username_or_email = opts["username"] || opts["email"]

    with {:ok, user} <- Accounts.authenticate(username_or_email, password) do
      render(conn, "show.json", user: user)
    end
  end

  def login(conn, %{"password" => password, "note" => note} = opts) do
    username_or_email = opts["username"] || opts["email"]

    with {:ok, user} <- Accounts.authenticate(username_or_email, password),
         {:ok, %{token: token}} <- Accounts.create_user_token(user, note) do
      render(conn, "show.json", user: user, token: token)
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
