defmodule NervesHubWeb.Auth do
  use NervesHubWeb, :verified_routes

  import Phoenix.Controller
  import Plug.Conn

  alias NervesHub.Accounts
  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.OrgRole
  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Accounts.Permissions
  alias NervesHub.Accounts.PubSub, as: AccessPubSub
  alias NervesHub.Accounts.Scope
  alias NervesHub.Accounts.TwoFactor
  alias NervesHub.Accounts.User
  alias NervesHub.Accounts.UserToken

  # Make the remember me cookie valid for 60 days.
  # If you want bump or reduce this value, also change
  # the token expiry itself in UserToken.
  alias NervesHubWeb.API.ErrorJSON

  @max_age 60 * 60 * 24 * 60
  @remember_me_cookie "_nerves_hub_user_remember_me"
  @remember_me_options [sign: true, max_age: @max_age, same_site: "Lax"]

  @doc """
  How many days "Remember me" keeps someone signed in, for the sign-in page to
  state.
  """
  def remember_me_days(), do: div(@max_age, 60 * 60 * 24)

  # How long someone has, after their password, to type in their code.
  @two_factor_timeout_seconds 5 * 60

  @doc """
  Signs `user` in, once whoever is signing in has proven they are them, by
  password, Google or a password reset. Every sign-in goes through here.

  A user with two-factor authentication on isn't signed in yet: they're sent
  to type in a code (`/login/two-factor`), and `complete_two_factor/3` signs
  them in after. What's needed to finish is kept in the session meanwhile.

  Options:

    * `:flash` - an info message for the first page after signing in.
    * `:link_google` - link the Google account a Google sign-in left in the
      session (see `link_pending_google_account/2`), for the sign-ins that
      prove the account is theirs.
  """
  @spec sign_in(Plug.Conn.t(), User.t(), map(), keyword()) :: Plug.Conn.t()
  def sign_in(conn, %User{} = user, params \\ %{}, opts \\ []) do
    if TwoFactor.enabled?(user) do
      pending = %{
        "user_id" => user.id,
        "started_at" => System.os_time(:second),
        "remember_me" => params["remember_me"] == "true",
        "flash" => opts[:flash],
        "link_google" => Keyword.get(opts, :link_google, false)
      }

      conn
      |> put_session(:two_factor_pending, pending)
      |> redirect(to: ~p"/login/two-factor")
    else
      finish_sign_in(conn, user, params, opts[:flash], Keyword.get(opts, :link_google, false))
    end
  end

  @doc """
  The user a sign-in waiting for a two-factor code is for, unless there is
  none or it has waited too long.
  """
  @spec pending_two_factor_user(Plug.Conn.t()) :: {:ok, User.t()} | :error
  def pending_two_factor_user(conn) do
    with %{"user_id" => user_id, "started_at" => started_at} <- get_session(conn, :two_factor_pending),
         true <- System.os_time(:second) - started_at <= @two_factor_timeout_seconds,
         {:ok, %User{} = user} <- Accounts.get_user(user_id) do
      {:ok, user}
    else
      _ -> :error
    end
  end

  @doc """
  Finishes a sign-in `sign_in/4` sent to `/login/two-factor`, once the code
  was right. `flash` is added to what the sign-in was going to say.
  """
  @spec complete_two_factor(Plug.Conn.t(), User.t(), String.t() | nil) :: Plug.Conn.t()
  def complete_two_factor(conn, %User{} = user, flash \\ nil) do
    pending = get_session(conn, :two_factor_pending)
    params = if pending["remember_me"], do: %{"remember_me" => "true"}, else: %{}
    message = [pending["flash"], flash] |> Enum.reject(&is_nil/1) |> Enum.join(" ")

    finish_sign_in(conn, user, params, if(message != "", do: message), pending["link_google"])
  end

  @doc """
  Forgets a sign-in that was waiting for a two-factor code.
  """
  @spec cancel_two_factor(Plug.Conn.t()) :: Plug.Conn.t()
  def cancel_two_factor(conn), do: delete_session(conn, :two_factor_pending)

  defp finish_sign_in(conn, user, params, flash, link_google?) do
    conn = if flash, do: put_flash(conn, :info, flash), else: conn
    conn = if link_google?, do: link_pending_google_account(conn, user), else: conn

    log_in_user(conn, user, params)
  end

  # Logs the user in, once they have passed two-factor if they have it on.
  #
  # It renews the session ID and clears the whole session to avoid fixation
  # attacks, and sets a `:live_socket_id` key in the session, so LiveView
  # sessions are identified and automatically disconnected on log out.
  defp log_in_user(conn, user, params) do
    token = Accounts.create_user_session_token(user)
    user_return_to = get_session(conn, :login_redirect_path)

    conn
    |> renew_session()
    |> put_token_in_session(token)
    |> maybe_write_remember_me_cookie(token, params)
    |> redirect_after_login(user_return_to)
  end

  # Links the Google account a Google sign-in left in the session, waiting for
  # proof that `user`'s account belongs to whoever is signing in (see
  # `NervesHubWeb.OAuthController`). Only for the sign-ins that prove it: the
  # account's password, or a password reset. Signing in clears the session, so
  # a pending link is only ever tried once.
  defp link_pending_google_account(conn, %User{} = user) do
    with %{} = pending <- get_session(conn, :pending_google_link),
         {:ok, _user} <- Accounts.link_google_account(user, pending) do
      put_flash(conn, :info, "Your Google account is now connected.")
    else
      _ -> conn
    end
  end

  defp redirect_after_login(conn, return_to) do
    case return_to_target(return_to) do
      {:local, path} -> redirect(conn, to: path)
      {:external, url} -> redirect(conn, external: url)
      :default -> redirect(conn, to: signed_in_path(conn))
    end
  end

  @doc """
  Classifies a post-login `return_to` value.

  Local paths (`/...`) pass through unchanged. Absolute URLs are only honored
  when their origin is allow-listed in the `:external_login_return_urls` config
  (open-redirect protection) — this is what lets a login initiated by the
  separate `nerves_hub_mcp` app return to its OAuth consent page. Anything else
  falls back to the default signed-in path.
  """
  @spec return_to_target(String.t() | nil) :: {:local, String.t()} | {:external, String.t()} | :default
  def return_to_target(nil), do: :default
  def return_to_target("//" <> _), do: :default
  def return_to_target("/" <> _ = path), do: {:local, path}

  def return_to_target(url) when is_binary(url) do
    if allowed_external_return_url?(url), do: {:external, url}, else: :default
  end

  def return_to_target(_), do: :default

  # Browsers read a URL differently from `URI.parse/1` when it has a backslash,
  # whitespace or control characters, or credentials: for
  # `https://evil.example\@allowed.example/` the browser goes to evil.example
  # while `URI.parse/1` reports allowed.example as the host. None of those appear
  # in a real return URL, so any of them rules the URL out.
  defp allowed_external_return_url?(url) do
    if String.match?(url, ~r/[\\\s\x00-\x1f\x7f]/u) do
      false
    else
      allowed_external_origin?(url)
    end
  end

  defp allowed_external_origin?(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host, userinfo: nil} = uri when is_binary(scheme) and is_binary(host) ->
        Enum.any?(allowed_return_base_urls(), fn base ->
          base = URI.parse(base)
          base.scheme == uri.scheme and base.host == uri.host and base.port == uri.port
        end)

      _ ->
        false
    end
  end

  defp allowed_return_base_urls() do
    Application.get_env(:nerves_hub, :external_login_return_urls, [])
  end

  defp maybe_write_remember_me_cookie(conn, token, %{"remember_me" => "true"}) do
    put_resp_cookie(conn, @remember_me_cookie, token, @remember_me_options)
  end

  defp maybe_write_remember_me_cookie(conn, _token, _params) do
    conn
  end

  defp renew_session(conn) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  @doc """
  Logs the User out.

  It clears all session data for safety. See renew_session.
  """
  def log_out_user(conn) do
    user_token = get_session(conn, :user_token)
    user_token && Accounts.delete_user_session_token(user_token)

    _ =
      if live_socket_id = get_session(conn, :live_socket_id) do
        NervesHubWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
      end

    conn
    |> renew_session()
    |> delete_resp_cookie(@remember_me_cookie)
    |> redirect(to: ~p"/login")
  end

  @doc """
  Authenticates the User by looking into the session and remember me token.
  """
  def fetch_current_user(conn, _opts) do
    with {user_token, conn} <- ensure_user_token(conn),
         user_token when is_binary(user_token) <- user_token,
         %User{} = user <- Accounts.get_user_by_session_token(user_token) do
      # Preload orgs and products for the navigation bar
      # Since we've loaded everything then we can reuse it for plugs
      # further down the pipeline
      user = Accounts.get_user_with_all_orgs_and_products(user.id)

      assign(conn, :current_scope, Scope.for_user(user))
    else
      nil ->
        assign(conn, :current_scope, Scope.for_user(nil))
    end
  end

  def assign_org_to_scope(conn, _opts) do
    current_scope = conn.assigns.current_scope

    if current_scope && conn.params["org_name"] do
      membership = NervesHub.Accounts.get_membership_by_org_name!(current_scope, conn.params["org_name"])

      current_scope
      |> Scope.put_org(membership.org)
      |> Scope.put_role(OrgUser.assigned_role(membership))
      |> then(fn scope ->
        assign(conn, :current_scope, scope)
      end)
    else
      conn
    end
  end

  @doc """
  Stops a member without two-factor authentication at an org that requires
  it. The browser is sent to set it up; the API (`:api`) is refused with a
  403 saying why.

  Runs after `assign_org_to_scope/2`, so a request with no org passes.
  """
  def require_org_two_factor(conn, opts) do
    case conn.assigns.current_scope do
      %Scope{org: %Org{} = org, user: %User{} = user} ->
        if TwoFactor.meets_org_requirement?(org, user) do
          conn
        else
          refuse_without_two_factor(conn, org, opts)
        end

      _ ->
        conn
    end
  end

  defp refuse_without_two_factor(conn, org, :api) do
    conn
    |> put_status(:forbidden)
    |> put_view(ErrorJSON)
    |> render(:"403", message: two_factor_required_message(org))
    |> halt()
  end

  defp refuse_without_two_factor(conn, org, _opts) do
    conn
    |> put_flash(:error, two_factor_required_message(org))
    |> redirect(to: ~p"/account/two-factor")
    |> halt()
  end

  @doc """
  What a member without two-factor is told when an org that requires it
  turns them away.
  """
  @spec two_factor_required_message(Org.t()) :: String.t()
  def two_factor_required_message(%Org{name: name}) do
    "#{name} requires two-factor authentication. Turn it on to reach the organization again."
  end

  def assign_product_to_scope(conn, _opts) do
    current_scope = conn.assigns.current_scope

    if current_scope && conn.params["product_name"] do
      product = NervesHub.Products.get_by_name!(current_scope, conn.params["product_name"])

      assign(conn, :current_scope, Scope.put_product(current_scope, product))
    else
      conn
    end
  end

  def on_mount(:assign_org_to_scope, %{"org_name" => org_name}, _session, socket) do
    socket =
      case socket.assigns.current_scope do
        %{org: nil} = scope ->
          membership = NervesHub.Accounts.get_membership_by_org_name!(scope, org_name)

          scope
          |> Scope.put_org(membership.org)
          |> Scope.put_role(OrgUser.assigned_role(membership))
          |> then(fn scope ->
            Phoenix.Component.assign(socket, :current_scope, scope)
          end)

        _ ->
          socket
      end

    %Scope{org: org, user: user} = socket.assigns.current_scope

    # Checked on every mount, so live navigation into the org is stopped as
    # well as the first request (`require_org_two_factor/2`).
    if TwoFactor.meets_org_requirement?(org, user) do
      {:cont, watch_membership(socket)}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, two_factor_required_message(org))
        |> Phoenix.LiveView.redirect(to: ~p"/account/two-factor")

      {:halt, socket}
    end
  end

  def on_mount(:assign_org_to_scope, _params, _session, socket), do: {:cont, socket}

  def on_mount(:assign_product_to_scope, %{"product_name" => product_name}, _session, socket) do
    socket =
      case socket.assigns.current_scope do
        %{product: nil} = scope ->
          product = NervesHub.Products.get_by_name!(scope, product_name)

          Phoenix.Component.assign(socket, :current_scope, Scope.put_product(scope, product))

        _ ->
          socket
      end

    {:cont, socket}
  end

  def on_mount(:assign_product_to_scope, _params, _session, socket), do: {:cont, socket}

  def on_mount(:require_authenticated, _params, session, socket) do
    socket = mount_current_scope(socket, session)

    if socket.assigns.current_scope && socket.assigns.current_scope.user do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "You must log in to access this page.")
        |> Phoenix.LiveView.redirect(to: ~p"/login")

      {:halt, socket}
    end
  end

  def on_mount(:mount_current_scope, _params, session, socket) do
    {:cont, mount_current_scope(socket, session)}
  end

  defp mount_current_scope(socket, %{"user_token" => user_token} = _session) do
    Phoenix.Component.assign_new(socket, :current_scope, fn ->
      with user_token when is_binary(user_token) <- user_token,
           %User{} = user <- Accounts.get_user_by_session_token(user_token),
           %User{} = user <- Accounts.get_user_with_all_orgs_and_products(user.id) do
        Scope.for_user(user)
      else
        nil ->
          Scope.for_user(nil)
      end
    end)
  end

  defp mount_current_scope(socket, _session), do: socket

  # The member's role is read once, when the page mounts, and every permission
  # check on the page uses that copy. So when an admin changes the role, the
  # page mounts again, and everything it worked out from the old role is worked
  # out again from the new one. A member who has been removed is sent back to
  # their list of orgs.
  defp watch_membership(%{assigns: %{current_scope: %Scope{org: %Org{} = org, user: %User{} = user}}} = socket) do
    if Phoenix.LiveView.connected?(socket) do
      :ok = AccessPubSub.subscribe_membership(org.id, user.id)
      Phoenix.LiveView.attach_hook(socket, :org_membership, :handle_info, &membership_changed/2)
    else
      socket
    end
  end

  defp watch_membership(socket), do: socket

  defp membership_changed(
         {:org_membership_changed, org_id},
         %{assigns: %{current_scope: %{org: %{id: org_id}}}} = socket
       ) do
    %Scope{org: org, user: user} = scope = socket.assigns.current_scope

    socket =
      case Accounts.get_org_user(org, user) do
        {:ok, %OrgUser{} = org_user} ->
          if same_role?(scope, OrgUser.assigned_role(org_user)) do
            socket
          else
            socket
            |> Phoenix.LiveView.put_flash(:info, "Your role in #{org.name} has changed.")
            |> Phoenix.LiveView.push_navigate(to: socket.assigns.current_path)
          end

        {:error, :not_found} ->
          socket
          |> Phoenix.LiveView.put_flash(:error, "You're no longer a member of #{org.name}.")
          |> Phoenix.LiveView.push_navigate(to: ~p"/orgs")
      end

    {:halt, socket}
  end

  defp membership_changed(_message, socket), do: {:cont, socket}

  # A custom role can keep its id while what it grants changes, so it is the
  # same role only if it grants the same permissions too.
  defp same_role?(%Scope{role: %OrgRole{id: id}, permissions: permissions}, %OrgRole{id: id} = role) do
    Permissions.for_role(role) == permissions
  end

  defp same_role?(%Scope{role: role}, role) when is_atom(role), do: true
  defp same_role?(_scope, _role), do: false

  @doc """
  Used for routes that require the user to be authenticated.

  If you want to enforce the user email is confirmed before
  they use the application at all, here would be a good place.
  """
  def require_authenticated_user(conn, _opts) do
    if conn.assigns.current_scope && conn.assigns.current_scope.user do
      conn
    else
      conn
      # `current_path/1` keeps the query string, so deep links (e.g. an OAuth
      # `/oauth/authorize?client_id=...` request) survive the login round-trip.
      |> put_session("login_redirect_path", current_path(conn))
      |> put_flash(:error, "You must login to access this page.")
      |> maybe_store_return_to()
      |> redirect(to: ~p"/login")
      |> halt()
    end
  end

  defp ensure_user_token(conn) do
    if token = get_session(conn, :user_token) do
      {token, conn}
    else
      conn = fetch_cookies(conn, signed: [@remember_me_cookie])

      if token = conn.cookies[@remember_me_cookie] do
        {token, put_token_in_session(conn, token)}
      else
        {nil, conn}
      end
    end
  end

  @doc """
  Used for routes that require the user to not be authenticated.
  """
  def redirect_if_user_is_authenticated(conn, _opts) do
    if conn.assigns[:current_scope] && conn.assigns.current_scope.user do
      conn
      |> redirect(to: signed_in_path(conn))
      |> halt()
    else
      conn
    end
  end

  defp put_token_in_session(conn, token) do
    conn
    |> put_session(:user_token, token)
    |> put_session(:live_socket_id, UserToken.live_socket_id(token))
  end

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :user_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn

  defp signed_in_path(_conn), do: ~p"/orgs"
end
