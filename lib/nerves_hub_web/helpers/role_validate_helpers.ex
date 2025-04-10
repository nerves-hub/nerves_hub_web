defmodule NervesHubWeb.Helpers.RoleValidateHelpers do
  @moduledoc false

  def init(opts), do: opts

  def call(conn, opts), do: validate_role(conn, opts)

  def validate_role(%{assigns: %{org: org, user: user}} = conn, org: role) do
    validate_org_user_role(conn, org, user, role)
  end

  def validate_role(%{assigns: %{device: device, user: user}} = conn, org: role) do
    validate_org_user_role(conn, device.org, user, role)
  end

  def validate_role(_conn, [{_key, value}]) do
    halt_role(value)
  end

  def validate_org_user_role(conn, org, user, role) do
    if NervesHub.Accounts.has_org_role?(org, user, role) do
      conn
    else
      halt_role(to_string(role))
    end
  end

  def halt_role(required_role) do
    raise NervesHubWeb.UnauthorizedError, required_role: required_role
  end
end
