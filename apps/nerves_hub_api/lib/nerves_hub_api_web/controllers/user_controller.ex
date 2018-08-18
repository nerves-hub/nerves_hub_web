defmodule NervesHubAPIWeb.UserController do
  use NervesHubAPIWeb, :controller

  alias NervesHubCore.Accounts
  alias NervesHubCore.{CertificateAuthority, Certificate}

  action_fallback(NervesHubAPIWeb.FallbackController)

  def me(%{assigns: %{user: user}} = conn, _params) do
    render(conn, "show.json", user: user)
  end

  def register(conn, params) do
    params =
      params
      |> Map.take(["name", "email", "password"])
      |> Map.put("org_name", params["name"])

    with {:ok, {_org, user}} <- Accounts.create_org_with_user(params) do
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
         {:ok, %{"cert" => cert}} <- CertificateAuthority.sign_user_csr(csr),
         {:ok, serial} <- Certificate.get_serial_number(cert),
         {:ok, _db_cert} <-
           Accounts.create_user_certificate(user, %{serial: serial, description: description}) do
      render(conn, "cert.json", cert: cert)
    end
  end
end
