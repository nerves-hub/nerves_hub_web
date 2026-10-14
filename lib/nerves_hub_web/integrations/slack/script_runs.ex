defmodule NervesHubWeb.Integrations.Slack.ScriptRuns do
  @moduledoc """
  Running a support script from Slack (`/nerveshub script <identifier>
  <name>`, `NervesHubWeb.Integrations.Slack.Commands`), and sharing its output.

  The output is shown only to whoever ran the script, since it can hold
  anything the device does, with a Share in channel button. Sharing is their
  decision, made once, by them: the output is kept briefly for it
  (`NervesHub.Integrations.Slack.ScriptResults`), and only the Slack user who ran the
  script can take it out and post it.

  Everything here answers through the `response_url` Slack sent with the
  command or the click, which works in private channels and direct messages,
  where the app may not be a member.
  """

  alias NervesHub.Accounts.User
  alias NervesHub.AuditLogs.DeviceTemplates
  alias NervesHub.Devices.Device
  alias NervesHub.Integrations.Slack.Client
  alias NervesHub.Integrations.Slack.ScriptResults
  alias NervesHub.Integrations.Slack.Users
  alias NervesHub.Scripts.Runner
  alias NervesHub.Scripts.Script
  alias NervesHubWeb.Integrations.Slack.Actions

  require Logger

  # Slack's limit on a section's text, less room for the code fences.
  @max_output 2900

  @doc """
  Runs the script on the device as `user`, and answers the command with its
  output, privately. Audited with the Slack user who ran it.
  """
  @spec run(map(), User.t(), Device.t(), Script.t()) :: :ok
  def run(request, %User{} = user, %Device{} = device, %Script{} = script) do
    :ok = DeviceTemplates.audit_script_run(user, device, script.name, Actions.via(request))

    message =
      case Runner.send(device, script) do
        {:ok, output} ->
          output = output |> to_string() |> truncate()

          id =
            ScriptResults.store(%{
              user_id: user.id,
              team_id: request.team_id,
              slack_user_id: request.slack_user_id,
              device_identifier: device.identifier,
              script_name: script.name,
              output: output
            })

          output_message(script.name, device.identifier, output, id)

        {:error, error} ->
          %{
            text:
              "`#{Actions.escape(script.name)}` on *#{Actions.escape(device.identifier)}* did not finish: #{Actions.escape(error)}"
          }
      end

    respond(request.response_url, Map.put(message, :response_type, "ephemeral"))
  end

  @doc """
  Shares a script's output in the channel, from a click on its Share in
  channel button. Returns what happened, for tests.
  """
  @spec share(%{
          result_id: String.t(),
          team_id: String.t(),
          slack_user_id: String.t(),
          response_url: String.t() | nil
        }) :: :ok | {:error, :gone | :not_yours | :not_linked}
  def share(%{result_id: id, team_id: team_id, slack_user_id: slack_user_id, response_url: url}) do
    with {:ok, result} <- ScriptResults.take(id, team_id, slack_user_id),
         %User{id: user_id} = user when user_id == result.user_id <- Users.use_link(team_id, slack_user_id) do
      name = Actions.escape(user.name)
      script = Actions.escape(result.script_name)
      identifier = Actions.escape(result.device_identifier)

      :ok =
        respond(url, %{
          response_type: "in_channel",
          replace_original: false,
          text: "#{name} shared the output of #{script} on #{identifier}",
          blocks: [
            section("#{name} shared the output of `#{script}` on *#{identifier}*:"),
            section("```#{Actions.escape(result.output)}```")
          ]
        })

      # Their own copy, without the button now it has been used.
      respond(url, %{
        response_type: "ephemeral",
        replace_original: true,
        text: "Shared in the channel.",
        blocks: [
          section("`#{script}` on *#{identifier}*, shared in the channel:"),
          section("```#{Actions.escape(result.output)}```")
        ]
      })
    else
      {:error, :gone} ->
        refuse(url, :gone, "That output is no longer kept. Run the script again to share it.")

      {:error, :not_yours} ->
        refuse(url, :not_yours, "Only whoever ran the script can share its output.")

      _unlinked_or_relinked ->
        refuse(
          url,
          :not_linked,
          "Your Slack account is no longer linked to the #{Actions.platform()} account that ran the script."
        )
    end
  end

  defp output_message(script_name, identifier, output, result_id) do
    script = Actions.escape(script_name)
    identifier = Actions.escape(identifier)

    %{
      text: "#{script} on #{identifier}",
      blocks: [
        section("`#{script}` on *#{identifier}*:"),
        section("```#{Actions.escape(output)}```"),
        %{
          type: "actions",
          elements: [
            %{
              type: "button",
              action_id: "script.share",
              text: %{type: "plain_text", text: "Share in channel"},
              value: result_id
            }
          ]
        },
        %{
          type: "context",
          elements: [%{type: "mrkdwn", text: "Only you can see this. Sharing posts it to the channel, as you."}]
        }
      ]
    }
  end

  defp section(text), do: %{type: "section", text: %{type: "mrkdwn", text: text}}

  defp truncate(output) do
    if String.length(output) > @max_output do
      String.slice(output, 0, @max_output) <> "\n… (cut short at #{@max_output} characters)"
    else
      output
    end
  end

  defp refuse(url, reason, text) do
    :ok = respond(url, %{response_type: "ephemeral", replace_original: false, text: text})
    {:error, reason}
  end

  defp respond(url, message) when is_binary(url) do
    case Client.respond(url, message) do
      {:ok, _} -> :ok
      {:error, error} -> Logger.warning("Could not answer Slack about a support script: #{inspect(error)}")
    end

    :ok
  end

  defp respond(_url, _message), do: :ok
end
