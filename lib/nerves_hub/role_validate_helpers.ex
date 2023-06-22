defmodule NervesHub.RoleValidateHelpers do
  def init(opts), do: opts

  def call(conn, opts), do: validate_role(conn, opts)

  def validate_role(%{assigns: %{org: org, user: user}} = conn, org: role) do
    validate_org_user_role(conn, org, user, role)
  end

  def validate_role(conn, [{key, value}]) do
    halt_role(conn, "#{key} #{value}")
  end

  def validate_org_user_role(conn, org, user, role) do
    if NervesHub.Accounts.has_org_role?(org, user, role) do
      conn
    else
      halt_role(conn, "org " <> to_string(role))
    end
  end

  def halt_role(conn, role) do
    conn
    |> Plug.Conn.put_resp_header("content-type", "application/json")
    |> Plug.Conn.send_resp(403, Jason.encode!(%{status: "missing required role: #{role}"}))
    |> Plug.Conn.halt()
  end
end
