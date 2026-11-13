defmodule NervesHub.Integrations.Slack do
  @moduledoc """
  NervesHub's Slack app: the Slack workspaces it is installed in, and the
  organizations connected to them.

  An organization admin connects a workspace by installing the app there
  through Slack's OAuth flow (`NervesHubWeb.Integrations.Slack.OAuthController`). Slack issues
  one bot token per workspace, kept on the `NervesHub.Integrations.Slack.Workspace`;
  each organization connected to the workspace has a
  `NervesHub.Integrations.Slack.Connection`. The token is revoked when the last
  organization disconnects, and the workspace is forgotten when Slack says
  the app was removed from it (`handle_event/2`).

  The integration is off unless the instance has a Slack app configured
  (`configured?/0`). `docs/slack.md` describes setting one up.
  """

  import Ecto.Query

  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.Scope
  alias NervesHub.AuditLogs.OrgTemplates
  alias NervesHub.Integrations
  alias NervesHub.Integrations.Slack.Client
  alias NervesHub.Integrations.Slack.Connection
  alias NervesHub.Integrations.Slack.Workspace
  alias NervesHub.Repo

  require Logger

  # Requested at install, including those only later features use, so that a
  # workspace connected now does not have to be reconnected as they arrive.
  # Slack only grants new scopes by installing the app again.
  @scopes ~w(chat:write chat:write.public channels:read groups:read commands links:read links:write)

  @authorize_url "https://slack.com/oauth/v2/authorize"

  @doc """
  Whether this instance has a Slack app: its client id and client secret
  are set, and a way for Slack to reach it, either a signing secret for
  Slack's requests (`request_urls?/0`) or an app-level token for Socket Mode
  (`socket_mode?/0`).
  """
  @spec configured?() :: boolean()
  def configured?() do
    set?(:client_id) and set?(:client_secret) and (set?(:signing_secret) or set?(:app_token))
  end

  @doc """
  Whether Slack sends its events, button clicks and slash commands to the
  instance's `/integrations/slack/` URLs, which takes the signing secret
  that proves a request came from Slack.
  """
  @spec request_urls?() :: boolean()
  def request_urls?(), do: configured?() and set?(:signing_secret)

  @doc """
  Whether the instance opens connections to Slack for its events, button
  clicks and slash commands instead (Socket Mode), which takes an app-level
  token. For an instance Slack cannot reach, such as one behind a VPN
  (`NervesHubWeb.Integrations.Slack.Socket`).
  """
  @spec socket_mode?() :: boolean()
  def socket_mode?(), do: configured?() and set?(:app_token)

  defp set?(key), do: config(key) not in [nil, ""]

  @doc false
  def config(key), do: Application.get_env(:nerves_hub, __MODULE__, [])[key]

  @doc "The bot scopes the app asks a workspace for."
  @spec scopes() :: [String.t()]
  def scopes(), do: @scopes

  @doc """
  Where to send a person to install the app in a workspace. Slack sends them
  back to `redirect_uri` with `state`, which the caller has tied to their
  session.
  """
  @spec authorize_url(String.t(), String.t()) :: String.t()
  def authorize_url(state, redirect_uri) do
    query =
      URI.encode_query(%{
        client_id: config(:client_id),
        scope: Enum.join(@scopes, ","),
        redirect_uri: redirect_uri,
        state: state
      })

    @authorize_url <> "?" <> query
  end

  @doc """
  The organization's workspace connections, oldest first, with the channels
  each sends events to.
  """
  @spec list_connections(Org.t()) :: [Connection.t()]
  def list_connections(%Org{id: org_id}) do
    Connection
    |> where(org_id: ^org_id)
    |> order_by(asc: :inserted_at, asc: :id)
    |> preload([:workspace, :connected_by, subscriptions: :products])
    |> Repo.all()
  end

  @doc "One of the organization's connections. Raises if it has none with that id."
  @spec get_connection!(Org.t(), pos_integer() | String.t()) :: Connection.t()
  def get_connection!(%Org{id: org_id}, id) do
    Connection
    |> where(id: ^id, org_id: ^org_id)
    |> preload(:workspace)
    |> Repo.one!()
  end

  @doc """
  Finishes an install: exchanges the `code` Slack's OAuth flow returned for
  the workspace's bot token, and connects the workspace to the scope's
  organization.

  Installing again in a workspace that is already connected refreshes its
  token and scopes. Organization-wide installs on Enterprise Grid are refused
  with `{:error, :enterprise_install}`: they have no single workspace.
  """
  @spec connect(Scope.t(), String.t(), String.t()) ::
          {:ok, Connection.t()} | {:error, :enterprise_install | String.t() | Ecto.Changeset.t()}
  def connect(%Scope{org: org, user: user}, code, redirect_uri) do
    with {:ok, access} <- Client.oauth_access(code, redirect_uri),
         {:ok, attrs} <- workspace_attrs(access) do
      Repo.transact(fn ->
        with {:ok, workspace} <- upsert_workspace(attrs),
             {:ok, connection} <- find_or_insert_connection(org, workspace, user) do
          :ok = OrgTemplates.audit_slack_connected(user, org, workspace)
          {:ok, Repo.preload(connection, [:workspace, :connected_by])}
        end
      end)
    end
  end

  defp workspace_attrs(%{"is_enterprise_install" => true}), do: {:error, :enterprise_install}

  defp workspace_attrs(
         %{
           "token_type" => "bot",
           "access_token" => token,
           "app_id" => app_id,
           "bot_user_id" => bot_user_id,
           "team" => %{"id" => team_id, "name" => team_name}
         } = access
       ) do
    {:ok,
     %{
       team_id: team_id,
       team_name: team_name,
       enterprise_id: get_in(access, ["enterprise", "id"]),
       app_id: app_id,
       bot_user_id: bot_user_id,
       bot_token: token,
       scopes: String.split(access["scope"] || "", ",", trim: true)
     }}
  end

  defp workspace_attrs(_access), do: {:error, "Slack's answer did not include a bot token"}

  defp upsert_workspace(attrs) do
    %Workspace{}
    |> Workspace.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:team_name, :enterprise_id, :app_id, :bot_user_id, :bot_token, :scopes, :updated_at]},
      conflict_target: :team_id,
      returning: true
    )
  end

  defp find_or_insert_connection(org, workspace, user) do
    case Repo.get_by(Connection, org_id: org.id, workspace_id: workspace.id) do
      nil -> org |> Connection.create_changeset(workspace, user) |> Repo.insert()
      connection -> {:ok, connection}
    end
  end

  @doc """
  Disconnects the organization from a workspace.

  When it was the last organization connected there, the workspace's bot
  token is revoked, which removes the app from the workspace, and the
  workspace is forgotten. Otherwise the token stays: the other organizations
  still use it.
  """
  @spec disconnect(Scope.t(), Connection.t()) :: :ok
  def disconnect(%Scope{org: org, user: user}, %Connection{} = connection) do
    {:ok, orphaned} =
      Repo.transact(fn ->
        # Locked so that an organization connecting at the same moment either
        # sees the workspace deleted or keeps it from being deleted.
        workspace =
          Workspace
          |> where(id: ^connection.workspace_id)
          |> lock("FOR UPDATE")
          |> Repo.one!()

        {:ok, _} = Repo.delete(connection)
        :ok = OrgTemplates.audit_slack_disconnected(user, org, workspace)

        if Repo.exists?(where(Connection, workspace_id: ^workspace.id)) do
          {:ok, nil}
        else
          {:ok, Repo.delete!(workspace)}
        end
      end)

    # The connection's channel subscriptions went with it.
    :ok = Integrations.invalidate(org.id)

    if orphaned, do: revoke(orphaned)

    :ok
  end

  # After the commit, so the database does not wait on Slack. Should Slack
  # not answer, the app stays in the workspace with a token nobody holds any
  # more; whoever administers the workspace can remove it there.
  defp revoke(%Workspace{bot_token: token, team_id: team_id}) do
    case Client.revoke(token) do
      {:ok, _} -> :ok
      {:error, error} -> Logger.warning("Could not revoke the Slack bot token for workspace #{team_id}: #{error}")
    end
  end

  @doc """
  Acts on an event Slack sent about workspace `team_id` (Events API,
  `event_callback`). The app being removed from the workspace, or its bot
  token being revoked, disconnects every organization connected there.
  Other events are ignored.

  Slack retries an event it thinks was missed, so this can see the same event
  twice; handling one is idempotent.
  """
  @spec handle_event(String.t(), map()) :: :ok
  def handle_event(team_id, %{"type" => "app_uninstalled"}),
    do: remove_workspace(team_id, "the app was removed from it")

  def handle_event(team_id, %{"type" => "tokens_revoked", "tokens" => %{"bot" => [_ | _] = bot_user_ids}}) do
    case Repo.get_by(Workspace, team_id: team_id) do
      %Workspace{bot_user_id: bot_user_id} = workspace ->
        if bot_user_id in bot_user_ids do
          remove_workspace(workspace.team_id, "its bot token was revoked")
        else
          :ok
        end

      nil ->
        :ok
    end
  end

  def handle_event(_team_id, _event), do: :ok

  defp remove_workspace(team_id, reason) do
    {:ok, org_ids} =
      Repo.transact(fn ->
        Workspace
        |> where(team_id: ^team_id)
        |> preload(connections: :org)
        |> Repo.one()
        |> case do
          nil ->
            {:ok, []}

          workspace ->
            for connection <- workspace.connections do
              :ok = OrgTemplates.audit_slack_removed(connection.org, workspace, reason)
            end

            _ = Repo.delete!(workspace)
            {:ok, Enum.map(workspace.connections, & &1.org_id)}
        end
      end)

    # Their channel subscriptions went with the workspace.
    Enum.each(org_ids, &Integrations.invalidate/1)
  end
end
