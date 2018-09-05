defmodule NervesHubAPIWeb.UserController do
  use NervesHubAPIWeb, :controller

  alias NervesHubCore.Accounts
  alias NervesHubCore.{CertificateAuthority, Certificate}

  action_fallback(NervesHubAPIWeb.FallbackController)

  defp whitelist(params, keys) do
    keys
    |> Enum.into(%{}, fn x -> {x, params[to_string(x)]} end)
  end

  def me(%{assigns: %{user: user}} = conn, _params) do
    render(conn, "show.json", user: user)
  end

  def register(conn, params) do
    params =
      params
      |> whitelist([:username, :email, :password])
      |> Map.put(:orgs, [%{name: params["username"]}])

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
         {:ok, %{"cert" => cert}} <- CertificateAuthority.sign_user_csr(csr),
         {:ok, serial} <- Certificate.get_serial_number(cert),
         {:ok, _db_cert} <-
           Accounts.create_user_certificate(user, %{serial: serial, description: description}) do
      render(conn, "cert.json", cert: cert)
    end
  end
end
