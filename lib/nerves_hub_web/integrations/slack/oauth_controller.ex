defmodule NervesHubWeb.Integrations.Slack.OAuthController do
  @moduledoc """
  Connects a Slack workspace to an organization, through Slack's OAuth flow,
  and links a person's Slack account to their NervesHub account, through
  Sign in with Slack.

  `install` sends an admin to Slack to install NervesHub's app, with a random
  `state` kept in their session alongside the organization. Slack sends them
  back to `callback`, which only accepts the `state` it gave out, so a
  callback forged by someone else, or replayed from another session, cannot
  attach a workspace to an organization. The organization's role is read
  again when they come back, in case it changed meanwhile.
  """
  use NervesHubWeb, :controller

  alias NervesHub.Accounts
  alias NervesHub.Accounts.Scope
  alias NervesHub.Branding
  alias NervesHub.Integrations.Slack
  alias NervesHub.Integrations.Slack.Users
  alias NervesHubWeb.Helpers.Authorization

  @session_key :slack_install
  @link_session_key :slack_link

  def install(%{assigns: %{current_scope: scope}} = conn, _params) do
    if !Slack.configured?(), do: raise(NervesHubWeb.NotFoundError)

    Authorization.authorized!(:"slack_connection:create", scope)

    state = 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

    conn
    |> put_session(@session_key, %{"state" => state, "org_name" => scope.org.name})
    |> redirect(external: Slack.authorize_url(state, redirect_uri()))
  end

  def callback(conn, params) do
    pending = get_session(conn, @session_key)
    conn = delete_session(conn, @session_key)

    with %{"state" => expected, "org_name" => org_name} <- pending,
         state when is_binary(state) <- params["state"],
         true <- Plug.Crypto.secure_compare(expected, state) do
      scope = org_scope(conn.assigns.current_scope, org_name)
      Authorization.authorized!(:"slack_connection:create", scope)

      finish(conn, scope, params)
    else
      _ ->
        conn
        |> put_flash(:error, "That Slack request did not start here, or has expired. Try adding the workspace again.")
        |> redirect(to: ~p"/orgs")
    end
  end

  defp finish(conn, scope, %{"code" => code}) when is_binary(code) do
    case Slack.connect(scope, code, redirect_uri()) do
      {:ok, connection} ->
        conn
        |> put_flash(:info, "Connected the #{connection.workspace.team_name} Slack workspace.")
        |> redirect(to: integrations_path(scope))

      {:error, :enterprise_install} ->
        conn
        |> put_flash(
          :error,
          "#{Branding.friendly_platform_name()} connects to one Slack workspace at a time. Install it in a workspace rather than across your Enterprise Grid organization."
        )
        |> redirect(to: integrations_path(scope))

      {:error, reason} ->
        conn
        |> put_flash(:error, "Slack could not be connected: #{error_message(reason)}")
        |> redirect(to: integrations_path(scope))
    end
  end

  # Slack sends `error=access_denied` when the person cancelled.
  defp finish(conn, scope, _params) do
    conn
    |> put_flash(:info, "Slack was not connected.")
    |> redirect(to: integrations_path(scope))
  end

  # The callback's URL names no organization (Slack has one redirect URL for
  # every install), so the organization comes from the session, and the
  # person's membership of it is looked up as the router does for org pages.
  defp org_scope(scope, org_name) do
    membership = Accounts.get_membership_by_org_name!(scope, org_name)

    scope
    |> Scope.put_org(membership.org)
    |> Scope.put_role(membership.role)
  end

  @doc """
  Starts Sign in with Slack, for linking the signed in person's Slack
  account. The `state` Slack carries back is kept in their session, so a
  sign-in started anywhere else (by somebody hoping to link their own Slack
  account to this person's NervesHub account) is refused at the callback.
  """
  def start_link(conn, params) do
    if !Slack.configured?(), do: raise(NervesHubWeb.NotFoundError)

    state = 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

    conn
    |> put_session(@link_session_key, state)
    |> redirect(external: Users.authorize_url(state, link_redirect_uri(), team(params["team"])))
  end

  def link_callback(conn, params) do
    expected = get_session(conn, @link_session_key)
    conn = delete_session(conn, @link_session_key)

    with true <- is_binary(expected) and is_binary(params["state"]),
         true <- Plug.Crypto.secure_compare(expected, params["state"]) do
      finish_link(conn, params)
    else
      _ ->
        conn
        |> put_flash(:error, "That Slack sign-in did not start here, or has expired. Try again.")
        |> redirect(to: ~p"/integrations/slack/link")
    end
  end

  defp finish_link(conn, %{"code" => code}) when is_binary(code) do
    case Users.link(conn.assigns.current_scope.user, code, link_redirect_uri()) do
      {:ok, link} ->
        conn
        |> put_flash(
          :info,
          "Linked #{link.slack_name || "your Slack account"} in #{link.team_name || "Slack"}. Go back to Slack and click the button again."
        )
        |> redirect(to: ~p"/account")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Slack could not be linked: #{error_message(reason)}")
        |> redirect(to: ~p"/integrations/slack/link")
    end
  end

  defp finish_link(conn, _params) do
    conn
    |> put_flash(:info, "Slack was not linked.")
    |> redirect(to: ~p"/integrations/slack/link")
  end

  # A workspace id, to suggest it at Slack. Anything else is dropped.
  defp team(team) when is_binary(team) do
    if Regex.match?(~r/\A[A-Z0-9]{1,32}\z/, team), do: team
  end

  defp team(_team), do: nil

  defp error_message(%Ecto.Changeset{}), do: "its answer could not be saved"

  defp error_message({:rate_limited, seconds}),
    do: "Slack asked #{Branding.friendly_platform_name()} to wait #{seconds} seconds"

  defp error_message(reason) when is_binary(reason), do: reason

  defp integrations_path(%Scope{org: org}), do: ~p"/org/#{org}/settings/integrations"

  # Must be identical in the install and in the token exchange, and listed as
  # a redirect URL in the Slack app's settings.
  defp redirect_uri(), do: url(~p"/integrations/slack/oauth/callback")

  # Listed as a redirect URL in the Slack app's settings too.
  defp link_redirect_uri(), do: url(~p"/integrations/slack/link/callback")
end
