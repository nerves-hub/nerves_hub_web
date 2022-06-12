defmodule NervesHubWWWWeb.SessionController do
  use NervesHubWWWWeb, :controller

  alias NervesHubWebCore.Accounts
  alias NervesHubWebCore.Accounts.{User, FidoCredential}
  require Logger
  alias NervesHubWWWWeb.SessionLive

  @user_id_key "auth_user_id"
  @fido_challenge_key "fido_challenge"

  def new(conn, _params) do
    with user_id when not is_nil(user_id) <- get_session(conn, @user_id_key),
         {:ok, user} <- Accounts.get_user(user_id) do
      redirect(conn, to: Routes.product_path(conn, :index, user.username))
    else
      _ ->
        render(conn, "new.html")
    end
  end

  def create(conn, %{
        "login" => %{"email_or_username" => email_or_username, "password" => password}
      }) do
    case Accounts.authenticate(email_or_username, password) do
      {:ok, %User{fido_credentials: []} = user} ->
        # No fido credentials, we are done here
        Logger.info("User has no FIDO credentials")

        finalize_login(conn, user)

      {:ok, %User{} = user} ->
        Logger.info("User requires FIDO login")

        render_fido(conn, user)

      _ ->
        Logger.info("Login failed")

        conn
        |> put_flash(:error, "Login Failed")
        |> redirect(to: Routes.session_path(conn, :new))
    end
  end

  def fido(conn, %{
        "fido" => %{
          "raw_id" => raw_id,
          "authenticator_data" => auth_data_b64,
          "signature" => signature_b64,
          "client_data_json" => client_data_json_b64
        }
      }) do
    challenge = get_session(conn, @fido_challenge_key)

    with {:ok, %Wax.AuthenticatorData{}} <-
           Wax.authenticate(
             raw_id,
             Base.decode64!(auth_data_b64),
             Base.decode64!(signature_b64),
             Base.decode64!(client_data_json_b64),
             challenge
           ),
         {:ok, user} <- Accounts.get_user_by_fido_credential_id(raw_id) do
      finalize_login(conn, user)
    else
      _ ->
        conn
        |> put_flash(:error, "FIDO Verification failed")
        |> redirect(to: Routes.session_path(conn, :new))
    end
  end

  def delete(conn, _params) do
    conn
    |> delete_session(@user_id_key)
    |> redirect(to: "/")
  end

  defp render_fido(conn, %User{} = user) do
    challenge =
      Wax.new_authentication_challenge(
        Enum.map(user.fido_credentials, fn %FidoCredential{} = cred ->
          {cred.credential_id, cred.cose_key}
        end),
        []
      )

    conn
    |> put_session(@fido_challenge_key, challenge)
    |> live_render(SessionLive)
  end

  defp finalize_login(conn, %User{} = user) do
    conn
    |> delete_session(@fido_challenge_key)
    |> put_session(@user_id_key, user.id)
    |> redirect(to: redirect_path_after_login(conn, user))
  end

  defp redirect_path_after_login(conn, user) do
    get_session(conn, :login_redirect_path) || Routes.product_path(conn, :index, user.username)
  end
end
