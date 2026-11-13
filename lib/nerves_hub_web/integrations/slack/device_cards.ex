defmodule NervesHubWeb.Integrations.Slack.DeviceCards do
  @moduledoc """
  A device's card in Slack: its connection, firmware, health and product,
  with its buttons. `/nerveshub device <identifier>` shows it only to whoever
  asked (`NervesHubWeb.Integrations.Slack.Commands`), with a Share in channel button.

  Sharing posts the card to the channel, saying who shared it. It is built
  again when shared, so the channel sees the device as it is then, and the
  sharer's permission to see the device is checked again first. The button
  carries only the identifier.
  """

  alias NervesHub.Accounts.User
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.Health
  alias NervesHub.Integrations.Slack.Client
  alias NervesHub.Integrations.Slack.Messages
  alias NervesHub.Repo
  alias NervesHub.Tracker
  alias NervesHubWeb.Integrations.Slack.Actions

  require Logger

  @doc """
  The device's card for whoever asked, if they may see the device, as a
  private answer; otherwise why not.
  """
  @spec show(String.t(), String.t(), String.t()) :: %{:response_type => String.t(), optional(atom()) => term()}
  def show(team_id, slack_user_id, identifier) do
    case Actions.authorize(team_id, slack_user_id, identifier, :"device:view", "see that device") do
      {:ok, _user, device} -> device |> card(shareable: true) |> Map.put(:response_type, "ephemeral")
      {:error, _reason, message} -> private(message)
    end
  end

  @doc """
  Posts the device's card to the channel, from a click on its Share in
  channel button, if the clicker may still see the device. Returns what
  happened, for tests.
  """
  @type share() :: %{
          identifier: String.t(),
          team_id: String.t(),
          slack_user_id: String.t(),
          response_url: String.t() | nil
        }

  @spec share(share()) :: :ok | {:error, atom()}
  def share(%{identifier: identifier, team_id: team_id, slack_user_id: slack_user_id, response_url: url}) do
    case Actions.authorize(team_id, slack_user_id, identifier, :"device:view", "see that device") do
      {:ok, user, device} ->
        card = card(device, shared_by: user)
        respond(url, Map.merge(card, %{response_type: "in_channel", replace_original: false}))

      {:error, reason, message} ->
        :ok = respond(url, Map.put(private(message), :replace_original, false))
        {:error, reason}
    end
  end

  @doc """
  The device's card: its connection, firmware, health and product, with its
  buttons. `opts`:

    * `shared_by:` the `User` sharing it, which the heading names
    * `shareable: true` adds Share in channel
    * `buttons: false` leaves the buttons out, for a link preview
      (`NervesHubWeb.Integrations.Slack.Unfurls`)
  """
  @spec card(Device.t(), keyword()) :: %{text: String.t(), blocks: [map()]}
  def card(%Device{} = device, opts \\ []) do
    device = Repo.preload(device, [:product, :org, :latest_connection])
    identifier = Actions.escape(device.identifier)
    online? = Tracker.online?(device)

    fields =
      Enum.map(
        [
          {"Connection", if(online?, do: "Online", else: offline_since(device))},
          {"Firmware", firmware_version(device)},
          {"Health", health(device)},
          {"Product", Actions.escape(device.product.name)}
        ],
        fn {label, value} -> %{type: "mrkdwn", text: "*#{label}*\n#{value}"} end
      )

    heading =
      case opts[:shared_by] do
        %User{name: name} -> "#{Actions.escape(name)} shared *#{identifier}*:"
        nil -> "*#{identifier}*"
      end

    buttons = Messages.device_buttons(device.org.name, device.product.name, device.identifier)

    buttons =
      if opts[:shareable] do
        Map.update!(buttons, :elements, fn elements ->
          elements ++
            [
              %{
                type: "button",
                action_id: "device.share",
                text: %{type: "plain_text", text: "Share in channel"},
                value: device.identifier
              }
            ]
        end)
      else
        buttons
      end

    section = %{type: "section", text: %{type: "mrkdwn", text: heading}, fields: fields}

    %{
      text: "#{identifier}: #{if online?, do: "online", else: "offline"}",
      blocks: if(Keyword.get(opts, :buttons, true), do: [section, buttons], else: [section])
    }
  end

  defp offline_since(%Device{latest_connection: %{last_seen_at: %DateTime{} = last_seen}}) do
    "Offline, last seen <!date^#{DateTime.to_unix(last_seen)}^{date_short_pretty} at {time}|#{DateTime.to_iso8601(last_seen)}>"
  end

  defp offline_since(_device), do: "Offline"

  defp firmware_version(%Device{firmware_metadata: %{version: version}}) when is_binary(version),
    do: Actions.escape(version)

  defp firmware_version(_device), do: "Unknown"

  defp health(device) do
    case Health.current_status(device.id) do
      nil -> "Not judged yet"
      status -> to_string(status)
    end
  end

  # A refusal is text, except the one asking the Slack user to link their
  # account, which is a whole message.
  defp private(text) when is_binary(text), do: %{response_type: "ephemeral", text: text}
  defp private(%{} = message), do: Map.put(message, :response_type, "ephemeral")

  defp respond(url, message) when is_binary(url) do
    case Client.respond(url, message) do
      {:ok, _} -> :ok
      {:error, error} -> Logger.warning("Could not share a device in Slack: #{inspect(error)}")
    end

    :ok
  end

  defp respond(_url, _message), do: :ok
end
