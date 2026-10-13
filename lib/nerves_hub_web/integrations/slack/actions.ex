defmodule NervesHubWeb.Integrations.Slack.Actions do
  @moduledoc """
  What a person can do to a device from Slack: the Reboot and Identify
  buttons on NervesHub's messages about a single device
  (`NervesHub.Integrations.Slack.Messages`).

  A click is done as the NervesHub user the Slack user linked
  (`NervesHub.Integrations.Slack.Users`), and only if, at that moment:

    * the device's organization is connected to the Slack workspace the
      click came from,
    * the NervesHub user is a member of that organization, and their role
      there has the permission the action needs, as it would in NervesHub,
    * the device is online, since both actions are messages to it.

  Nothing on the message is trusted for any of this: the button carries only
  the device's identifier, and everything else is looked up when the click
  arrives. A refusal, and the link to connect an account, are shown only to
  the person who clicked. What was done is posted in the message's thread,
  for everyone in the channel to see who did it.

  Slack wants its interaction request answered within three seconds, so
  `handle_interaction/1` answers at once and the action runs in a task.

  This lives in the web layer, beside the controller Slack's requests reach,
  because the permission each action needs is checked the way the dashboard
  checks it (`NervesHubWeb.Helpers.Authorization`).
  """

  import Ecto.Query

  alias NervesHub.Accounts
  alias NervesHub.Accounts.Org
  alias NervesHub.DeviceEvents
  alias NervesHub.Devices.Device
  alias NervesHub.Integrations.Slack.Client
  alias NervesHub.Integrations.Slack.Connection
  alias NervesHub.Integrations.Slack.Users
  alias NervesHub.Integrations.Slack.Workspace
  alias NervesHub.Repo
  alias NervesHub.Tracker
  alias NervesHubWeb.Helpers.Authorization

  require Logger

  @actions %{
    "device.reboot" => %{permission: :"device:reboot", verb: "reboot"},
    "device.identify" => %{permission: :"device:identify", verb: "identify itself"}
  }

  @typedoc "Where a click came from, read from Slack's interaction payload."
  @type click() :: %{
          action_id: String.t(),
          identifier: String.t(),
          team_id: String.t(),
          slack_user_id: String.t(),
          slack_username: String.t() | nil,
          response_url: String.t() | nil,
          channel_id: String.t() | nil,
          message_ts: String.t() | nil
        }

  @doc "The action ids NervesHub's buttons use."
  @spec action_ids() :: [String.t()]
  def action_ids(), do: Map.keys(@actions)

  @doc """
  Acts on an interaction payload from Slack. Clicks on NervesHub's action
  buttons are carried out in a task; anything else (a link button, which
  Slack reports too) is ignored.
  """
  @spec handle_interaction(map()) :: :ok
  def handle_interaction(%{"type" => "block_actions", "actions" => actions} = payload) when is_list(actions) do
    for action <- actions, click = click(payload, action), not is_nil(click) do
      {:ok, _pid} = Task.Supervisor.start_child(NervesHub.TaskSupervisor, fn -> perform(click) end)
    end

    :ok
  end

  def handle_interaction(_payload), do: :ok

  defp click(payload, %{"action_id" => action_id, "value" => identifier})
       when is_map_key(@actions, action_id) and is_binary(identifier) do
    case payload do
      %{"team" => %{"id" => team_id}, "user" => %{"id" => slack_user_id} = slack_user} ->
        %{
          action_id: action_id,
          identifier: identifier,
          team_id: team_id,
          slack_user_id: slack_user_id,
          slack_username: slack_user["username"] || slack_user["name"],
          response_url: payload["response_url"],
          channel_id: get_in(payload, ["container", "channel_id"]) || get_in(payload, ["channel", "id"]),
          message_ts: get_in(payload, ["container", "message_ts"]) || get_in(payload, ["message", "ts"])
        }

      _ ->
        nil
    end
  end

  defp click(_payload, _action), do: nil

  @doc """
  Carries out a click, or says why not. Returns what happened, for tests.
  """
  @spec perform(click()) :: {:ok, String.t()} | {:error, atom()}
  def perform(click) do
    %{permission: permission, verb: verb} = Map.fetch!(@actions, click.action_id)

    case authorize(click.team_id, click.slack_user_id, click.identifier, permission, "ask a device to #{verb}") do
      {:ok, user, device} ->
        if Tracker.online?(device) do
          {:ok, _device} = act(click.action_id, device, user, via(click))
          :ok = announce(click, done(click.action_id, user, device))
          {:ok, click.action_id}
        else
          refuse(click, :offline, offline_message(device, verb))
        end

      {:error, reason, message} ->
        refuse(click, reason, message)
    end
  end

  @doc """
  Who a Slack user is in NervesHub, and the device they named, if they may
  do what `permission` allows to it; otherwise why not, worded for the Slack
  user (`what` finishes "Your role in NervesHub does not let you ...").

  The checks, made fresh each time: the Slack user linked a NervesHub
  account, the device exists, its organization is connected to the
  workspace the request came from, and the NervesHub user is a member there
  whose role has `permission`. Shared by buttons and slash commands
  (`NervesHubWeb.Integrations.Slack.Commands`).
  """
  @spec authorize(String.t(), String.t(), String.t(), atom(), String.t()) ::
          {:ok, Accounts.User.t(), Device.t()} | {:error, atom(), String.t() | map()}
  def authorize(team_id, slack_user_id, identifier, permission, what) do
    with {:user, %Accounts.User{} = user} <- {:user, Users.linked_user(team_id, slack_user_id)},
         {:device, %Device{} = device} <- {:device, device(identifier)},
         {:connected, true} <- {:connected, connected?(device.org_id, team_id)},
         {:member, {:ok, org_user}} <- {:member, Accounts.get_org_user(device.org, user)},
         {:allowed, true} <- {:allowed, Authorization.authorized?(permission, org_user.role)} do
      {:ok, user, device}
    else
      {:user, nil} ->
        {:error, :not_linked, link_message(team_id)}

      {:device, nil} ->
        {:error, :no_device, "#{escape(identifier)} is not in NervesHub."}

      {:connected, false} ->
        {:error, :not_connected,
         "This Slack workspace is not connected to the organization #{escape(identifier)} belongs to."}

      {:member, {:error, :not_found}} ->
        {:error, :not_member,
         "Your NervesHub account is not a member of the organization #{escape(identifier)} belongs to."}

      {:allowed, false} ->
        {:error, :not_allowed, "Your role in NervesHub does not let you #{what}."}
    end
  end

  @doc "What a device that is offline cannot be asked to do, worded for Slack."
  @spec offline_message(Device.t(), String.t()) :: String.t()
  def offline_message(device, verb) do
    "#{escape(device.identifier)} is offline, so NervesHub could not ask it to #{verb}."
  end

  defp device(identifier) do
    Device
    |> where(identifier: ^identifier)
    |> where([d], is_nil(d.deleted_at))
    |> join(:inner, [d], o in Org, on: o.id == d.org_id and is_nil(o.deleted_at))
    |> preload([:latest_connection, :org])
    |> Repo.one()
  end

  defp connected?(org_id, team_id) do
    Connection
    |> join(:inner, [c], w in Workspace, on: w.id == c.workspace_id)
    |> where([c, w], c.org_id == ^org_id and w.team_id == ^team_id)
    |> Repo.exists?()
  end

  defp act("device.reboot", device, user, via), do: DeviceEvents.reboot(device, user, via: via)
  defp act("device.identify", device, user, via), do: DeviceEvents.identify(device, user, via: via)

  @doc """
  Which Slack user it was, by id, for the audit log: the NervesHub user is
  who it was done as, and the Slack user is who asked.
  """
  @spec via(%{
          required(:slack_user_id) => String.t(),
          required(:slack_username) => String.t() | nil,
          required(:team_id) => String.t(),
          optional(atom()) => term()
        }) :: String.t()
  def via(request) do
    name = if request.slack_username, do: "@#{request.slack_username}, ", else: ""
    "Slack user #{request.slack_user_id} (#{name}workspace #{request.team_id})"
  end

  defp done("device.reboot", user, device),
    do: ":arrows_counterclockwise: #{escape(user.name)} rebooted *#{escape(device.identifier)}* from Slack."

  defp done("device.identify", user, device),
    do: ":mag: #{escape(user.name)} asked *#{escape(device.identifier)}* to identify itself, from Slack."

  @doc """
  The message that sends a Slack user who has not linked their NervesHub
  account to do so. Shown only to them.
  """
  @spec link_message(String.t()) :: %{text: String.t(), blocks: [map()]}
  def link_message(team_id) do
    url = NervesHubWeb.Endpoint.url() <> "/integrations/slack/link?" <> URI.encode_query(%{team: team_id})

    %{
      text: "Link your Slack account to NervesHub to act on devices from Slack.",
      blocks: [
        %{
          type: "section",
          text: %{
            type: "mrkdwn",
            text:
              "Link your Slack account to NervesHub to act on devices from Slack. You sign in to NervesHub, then with Slack, and what you then do from Slack is done as you in NervesHub, with your permissions there."
          }
        },
        %{
          type: "actions",
          elements: [
            %{
              type: "button",
              action_id: "account.link",
              text: %{type: "plain_text", text: "Link your account"},
              url: url,
              style: "primary"
            }
          ]
        }
      ]
    }
  end

  defp refuse(click, reason, message) do
    :ok = respond_privately(click, message)
    {:error, reason}
  end

  # Only the person who clicked sees it.
  defp respond_privately(%{response_url: url}, message) when is_binary(url) do
    message = if is_binary(message), do: %{text: message}, else: message

    case Client.respond(url, Map.merge(message, %{response_type: "ephemeral", replace_original: false})) do
      {:ok, _} -> :ok
      {:error, error} -> Logger.warning("Could not answer a Slack interaction: #{inspect(error)}")
    end

    :ok
  end

  defp respond_privately(_click, _message), do: :ok

  # In the message's thread, for the channel to see who did what.
  defp announce(%{channel_id: channel_id, message_ts: ts} = click, text) when is_binary(channel_id) and is_binary(ts) do
    with %Workspace{bot_token: token} <- Repo.get_by(Workspace, team_id: click.team_id),
         {:ok, _} <- Client.post_message(token, channel_id, %{text: text, blocks: []}, thread_ts: ts) do
      :ok
    else
      error ->
        Logger.warning("Could not post a Slack action to its thread: #{inspect(error)}")
        respond_privately(click, text)
    end
  end

  defp announce(click, text), do: respond_privately(click, text)

  @doc "Escapes Slack's mrkdwn control characters."
  @spec escape(term()) :: String.t()
  def escape(value) do
    String.replace(to_string(value), ["&", "<", ">"], fn
      "&" -> "&amp;"
      "<" -> "&lt;"
      ">" -> "&gt;"
    end)
  end
end
