defmodule NervesHubWWWWeb.AccountCertificateController do
  use NervesHubWWWWeb, :controller

  require Logger

  alias Ecto.Changeset
  alias NervesHubWebCore.{Certificate, CertificateAuthority}
  alias NervesHubWebCore.Accounts
  alias NervesHubWebCore.Accounts.UserCertificate

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

  def create(%{assigns: %{user: user}} = conn, %{"user_certificate" => user_certificate_params}) do
    username = user.email

    with {:ok, resp} <- CertificateAuthority.create_user_certificate(username),
         cert_pem <- Map.get(resp, "cert"),
         key <- Map.get(resp, "key"),
         {:ok, cert} <- X509.Certificate.from_pem(cert_pem),
         serial_number <- Certificate.get_serial_number(cert) do
      user_certificate_params = Map.put(user_certificate_params, "serial", serial_number)

      archive =
        create_certificate_archive(cert_pem, key)
        |> Base.encode64()

      {:ok, db_cert} = Accounts.create_user_certificate(user, user_certificate_params)

      conn
      |> redirect(to: account_certificate_path(conn, :show, db_cert, file: archive))
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "new.html", changeset: changeset)

      e ->
        Logger.error("Error while generating user certificate: #{inspect(e)}")
        send_resp(conn, 500, "An error occurered while creating the account certificate")
    end
  end

  def delete(%{assigns: %{user: user}} = conn, %{"id" => id}) do
    cert = Accounts.get_user_certificate!(user, id)
    {:ok, _cert} = Accounts.delete_user_certificate(cert)

    conn
    |> put_flash(:info, "Certificate deleted successfully.")
    |> redirect(to: account_certificate_path(conn, :index))
  end

  # Thanks to Hex for lending us this chunk of code.
  # NervesHub <3 Hex
  defp create_certificate_archive(cert, key) do
    {:ok, fd} = :file.open([], [:ram, :read, :write, :binary])
    {:ok, tar} = :erl_tar.init(fd, :write, &file_op/2)

    files = [
      {'user.pem', cert},
      {'user-key.pem', key}
    ]

    try do
      try do
        add_files(tar, files)
      after
        :erl_tar.close(fd)
      end

      {:ok, size} = :file.position(fd, :cur)
      {:ok, binary} = :file.pread(fd, 0, size)
      binary
    after
      :ok = :file.close(fd)
    end
  end

  defp file_op(:write, {fd, data}), do: :file.write(fd, data)
  defp file_op(:position, {fd, pos}), do: :file.position(fd, pos)
  defp file_op(:read2, {fd, size}), do: :file.read(fd, size)
  defp file_op(:close, _Fd), do: :ok

  def add_files(tar, files) when is_list(files) do
    Enum.map(files, &add_file(tar, &1))
  end

  def add_file(tar, {filename, contents}) when is_list(filename) and is_binary(contents) do
    :ok = :erl_tar.add(tar, contents, filename, [])
  end
end
