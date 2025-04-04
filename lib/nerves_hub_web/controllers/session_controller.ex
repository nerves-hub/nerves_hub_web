defmodule NervesHubWeb.SessionController do
  use NervesHubWeb, :controller

  alias NervesHub.Accounts
  alias NervesHubWeb.Auth

  def new(conn, params) do
    render(conn, "new.html", message: params["message"])
  end

  def create(conn, %{"login" => user_params}) do
    %{"email" => email, "password" => password} = user_params

    if user = Accounts.get_user_by_email_and_password(email, password) do
      Auth.log_in_user(conn, user, user_params)
    else
      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
      conn
      |> put_flash(:error, "Invalid email or password")
      |> put_flash(:email, String.slice(email, 0, 160))
      |> redirect(to: ~p"/login")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> NervesHubWeb.Auth.log_out_user()
  end
end
