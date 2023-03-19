defmodule NervesHubWeb.AccountCertificateController do
  use NervesHubWeb, :controller

  require Logger

  alias Ecto.Changeset
  alias NervesHub.Accounts
  alias NervesHub.Accounts.UserCertificate

  def index(%{assigns: %{user: user}} = conn, _params) do
    conn
    |> render(
      "index.html",
      certificates: Accounts.get_user_certificates(user)
    )
  end

  def new(conn, _params) do
    render(conn, "new.html", changeset: %Changeset{data: %UserCertificate{}})
  end

  def show(%{assigns: %{user: user}} = conn, %{"id" => id, "file" => file}) do
    cert = Accounts.get_user_certificate!(user, id)
    render(conn, "show.html", user_certificate: cert, file: file)
  end

  def show(%{assigns: %{user: user}} = conn, %{"id" => id}) do
    cert = Accounts.get_user_certificate!(user, id)
    render(conn, "show.html", user_certificate: cert, file: nil)
  end

  def download(%{assigns: %{user: _user}} = conn, %{"file" => file}) do
    archive = Base.decode64!(file)

    conn
    |> send_download({:binary, archive}, filename: "certificates.tar.gz")
  end

  def delete(%{assigns: %{user: user}} = conn, %{"id" => id}) do
    cert = Accounts.get_user_certificate!(user, id)
    {:ok, _cert} = Accounts.delete_user_certificate(cert)

    conn
    |> put_flash(:info, "Certificate deleted successfully.")
    |> redirect(to: Routes.account_certificate_path(conn, :index, user.username))
  end

  def add_files(tar, files) when is_list(files) do
    Enum.map(files, &add_file(tar, &1))
  end

  def add_file(tar, {filename, contents}) when is_list(filename) and is_binary(contents) do
    :ok = :erl_tar.add(tar, contents, filename, [])
  end
end
