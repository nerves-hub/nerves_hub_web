defmodule NervesHub.Integrations.Slack.Users do
  @moduledoc """
  Which NervesHub user a Slack user is.

  A NervesHub user links their Slack account by signing in with Slack
  (Slack's OpenID Connect flow, `NervesHubWeb.Integrations.Slack.OAuthController`) while signed
  in to NervesHub. The Slack user id and workspace come from Slack itself,
  read with the token Slack issues for that sign-in, so the link proves the
  person holding the NervesHub account also holds the Slack account.

  That is the point of signing in rather than following a link NervesHub
  hands the Slack user: a link can be passed to somebody else, and whoever
  confirmed it would lend their NervesHub account to the Slack user who
  passed it on. Nothing is matched by email either, since the workspace
  decides what email a Slack user has.
  """

  import Ecto.Query

  alias NervesHub.Accounts.User
  alias NervesHub.Integrations.Slack
  alias NervesHub.Integrations.Slack.Client
  alias NervesHub.Integrations.Slack.UserLink
  alias NervesHub.Integrations.Slack.Workspace
  alias NervesHub.Repo

  @authorize_url "https://slack.com/openid/connect/authorize"

  @doc """
  Where to send a NervesHub user to sign in with Slack. `team` (a workspace
  id) only suggests a workspace; who they sign in as is up to Slack.
  """
  @spec authorize_url(String.t(), String.t(), String.t() | nil) :: String.t()
  def authorize_url(state, redirect_uri, team \\ nil) do
    query =
      %{
        response_type: "code",
        scope: "openid profile",
        client_id: Slack.config(:client_id),
        state: state,
        redirect_uri: redirect_uri
      }
      |> then(fn query -> if team, do: Map.put(query, :team, team), else: query end)
      |> URI.encode_query()

    @authorize_url <> "?" <> query
  end

  @doc """
  Finishes a sign-in with Slack: exchanges the `code` for a token, asks Slack
  who it belongs to, and links that Slack user to `user`, replacing whoever
  they were linked to before.
  """
  @spec link(User.t(), String.t(), String.t()) :: {:ok, UserLink.t()} | {:error, Client.error()}
  def link(%User{} = user, code, redirect_uri) do
    with {:ok, %{"access_token" => token}} <- Client.openid_token(code, redirect_uri),
         {:ok, %{"https://slack.com/user_id" => slack_user_id, "https://slack.com/team_id" => team_id} = info} <-
           Client.openid_user_info(token) do
      %UserLink{
        user_id: user.id,
        team_id: team_id,
        slack_user_id: slack_user_id,
        slack_name: info["name"],
        team_name: info["https://slack.com/team_name"],
        linked_at: DateTime.utc_now()
      }
      |> Repo.insert(
        on_conflict: {:replace, [:user_id, :slack_name, :team_name, :linked_at, :updated_at]},
        conflict_target: [:team_id, :slack_user_id],
        returning: true
      )
    else
      {:ok, _unexpected} -> {:error, "Slack did not say who signed in"}
      error -> error
    end
  end

  @doc """
  The NervesHub user a Slack user is linked to, if any, for acting as them:
  records the link as used now, which Account Settings shows.
  """
  @spec use_link(String.t(), String.t()) :: User.t() | nil
  def use_link(team_id, slack_user_id) do
    case linked_user(team_id, slack_user_id) do
      nil ->
        nil

      user ->
        {_count, _} =
          UserLink
          |> where(team_id: ^team_id, slack_user_id: ^slack_user_id)
          |> Repo.update_all(set: [last_used_at: DateTime.utc_now()])

        user
    end
  end

  @doc "The NervesHub user a Slack user is linked to, if any."
  @spec linked_user(String.t(), String.t()) :: User.t() | nil
  def linked_user(team_id, slack_user_id) do
    User
    |> join(:inner, [u], l in UserLink, on: l.user_id == u.id)
    |> where([_u, l], l.team_id == ^team_id and l.slack_user_id == ^slack_user_id)
    |> where([u], is_nil(u.deleted_at))
    |> Repo.one()
  end

  @doc """
  The user's Slack links, with the workspace's current name where NervesHub
  still has it, or the name it had when linked.
  """
  @spec list_links(User.t()) :: [%{link: UserLink.t(), team_name: String.t() | nil}]
  def list_links(%User{id: user_id}) do
    UserLink
    |> where(user_id: ^user_id)
    |> join(:left, [l], w in Workspace, on: w.team_id == l.team_id)
    |> order_by([l], asc: l.linked_at)
    |> select([l, w], %{link: l, team_name: coalesce(w.team_name, l.team_name)})
    |> Repo.all()
  end

  @doc "Removes one of the user's Slack links."
  @spec unlink(User.t(), pos_integer()) :: :ok
  def unlink(%User{id: user_id}, id) do
    {_count, _} = UserLink |> where(id: ^id, user_id: ^user_id) |> Repo.delete_all()
    :ok
  end
end
