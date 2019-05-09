defmodule NervesHubWebCore.RoleValidateHelpers do
  def init(opts), do: opts

  def call(conn, opts), do: validate_role(conn, opts)

  def validate_role(%{assigns: %{org: org, user: user}} = conn, org: role) do
    validate_org_user_role(conn, org, user, role)
  end

  def validate_role(%{assigns: %{current_org: org, user: user}} = conn, org: role) do
    validate_org_user_role(conn, org, user, role)
  end

  def validate_role(
        %{assigns: %{product: %{org: %Ecto.Association.NotLoaded{}} = product}} = conn,
        product: role
      ) do
    product = NervesHubWebCore.Repo.preload(product, :org)

    conn
    |> Plug.Conn.assign(:product, product)
    |> validate_role(product: role)
  end

  def validate_role(%{assigns: %{user: user, product: %{org: org} = product}} = conn,
        product: role
      ) do
    cond do
      NervesHubWebCore.Accounts.has_org_role?(org, user, role) ->
        conn

      NervesHubWebCore.Products.has_product_role?(product, user, role) ->
        conn

      true ->
        halt_role(conn, "product " <> to_string(role))
    end
  end

  def validate_role(conn, [{key, value}]) do
    halt_role(conn, "#{key} #{value}")
  end

  def validate_org_user_role(conn, org, user, role) do
    if NervesHubWebCore.Accounts.has_org_role?(org, user, role) do
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
