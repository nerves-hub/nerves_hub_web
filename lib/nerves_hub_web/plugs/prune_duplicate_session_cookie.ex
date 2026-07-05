defmodule NervesHubWeb.Plugs.PruneDuplicateSessionCookie do
  @moduledoc """
  Clears a stale *host-only* `_nerves_hub_key` session cookie when the request
  carries a duplicate.

  The session cookie's `Domain` was widened to a shared parent (e.g.
  `.nervescloud.com`) so it can be shared for single sign-on with other apps
  running on a sibling subdomain. Browsers that still hold a *pre-migration*
  host-only cookie (scoped to the exact host, with no `Domain`) then end up with
  TWO `_nerves_hub_key` cookies. Both are sent on every request, and the server
  reads whichever the browser lists first, so the session becomes nondeterministic
  and login can fail.

  The request `Cookie` header does not expose each cookie's `Domain`, so we detect
  the situation by *count*: more than one `_nerves_hub_key=` means a duplicate is
  present. We then emit a host-only deletion (a `Set-Cookie` with no `Domain`,
  expired), which removes ONLY the host-only variant and leaves the canonical
  parent-domain cookie untouched. It is self-limiting: once the duplicate is gone
  the request no longer matches and the plug is a no-op.

  Guarded on `:session_cookie_domain` being configured. Without it (single-host or
  dev) a lone host-only cookie *is* the real session, so we never touch it.
  """

  @behaviour Plug

  import Plug.Conn

  @cookie "_nerves_hub_key"

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    if prune?(conn) do
      # Not `delete_resp_cookie/2`: that writes `conn.resp_cookies` keyed by name,
      # which `Plug.Session` overwrites with its parent-domain cookie of the same
      # name. A raw `Set-Cookie` with no `Domain` deletes only the host-only cookie
      # and coexists with the session's parent-domain `Set-Cookie`.
      prepend_resp_headers(conn, [
        {"set-cookie", "#{@cookie}=; path=/; max-age=0; secure; httponly; samesite=lax"}
      ])
    else
      conn
    end
  end

  defp prune?(conn), do: domain_scoped?() and duplicate_cookie?(conn)

  defp domain_scoped?(), do: not is_nil(Application.get_env(:nerves_hub, :session_cookie_domain))

  defp duplicate_cookie?(conn) do
    conn
    |> get_req_header("cookie")
    |> Enum.flat_map(&String.split(&1, ";"))
    |> Enum.map(&String.trim/1)
    |> Enum.count(&String.starts_with?(&1, @cookie <> "="))
    |> Kernel.>(1)
  end
end
