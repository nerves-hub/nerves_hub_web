defmodule NervesHubWeb.Integrations.Slack.Commands do
  @moduledoc """
  NervesHub's slash command in Slack (`/nerveshub` unless the instance's
  Slack app names it otherwise):

    * `device <identifier>`: the device's state, with its buttons and one
      for sharing it in the channel (`NervesHubWeb.Integrations.Slack.DeviceCards`)
    * `identify <identifier>` and `reboot <identifier>`: as the buttons do
    * `script <identifier>`: the product's support scripts
    * `script <identifier> <script name>`: runs one, and shows its output
    * `link`: links the Slack user's NervesHub account
    * `help`

  Each is done as the NervesHub user the Slack user linked, and checked as
  the buttons are (`NervesHubWeb.Integrations.Slack.Actions.authorize/5`): the device's
  organization connected to this workspace, and the user's role there
  allowing it at that moment.

  What a command shows is seen only by the person who typed it, script
  output included, since a script's output can be anything the device holds.
  A reboot or identify done is posted to the channel, so it sees who did
  what, as with the buttons.

  Slack wants an answer within three seconds, so everything is answered
  straight away except a script, which can take up to 30 seconds to run: it
  is acknowledged, then run in a task by `NervesHubWeb.Integrations.Slack.ScriptRuns`, which
  sends its output through the command's `response_url`, with a button for
  sharing it in the channel.
  """

  alias NervesHub.DeviceEvents
  alias NervesHub.Repo
  alias NervesHub.Scripts
  alias NervesHub.Tracker
  alias NervesHubWeb.Integrations.Slack.Actions
  alias NervesHubWeb.Integrations.Slack.DeviceCards
  alias NervesHubWeb.Integrations.Slack.ScriptRuns

  @typedoc "The slash command request, as Slack sent it."
  @type request() :: %{
          team_id: String.t(),
          slack_user_id: String.t(),
          slack_username: String.t() | nil,
          command: String.t(),
          response_url: String.t() | nil
        }

  @doc """
  Answers a slash command request, from Slack's form fields. Returns the
  answer to send straight back.
  """
  @spec handle(map()) :: map()
  def handle(%{"team_id" => team_id, "user_id" => slack_user_id} = params)
      when is_binary(team_id) and is_binary(slack_user_id) do
    request = %{
      team_id: team_id,
      slack_user_id: slack_user_id,
      slack_username: params["user_name"],
      command: params["command"] || "/nerveshub",
      response_url: params["response_url"]
    }

    if Actions.first_time?(params) do
      params
      |> Map.get("text", "")
      |> to_string()
      |> String.split()
      |> run(request)
    else
      private("This command was already answered.")
    end
  end

  def handle(_params), do: private("Slack did not say who sent this.")

  defp run([], request), do: help(request)
  defp run(["help" | _], request), do: help(request)
  defp run(["link" | _], request), do: request.team_id |> Actions.link_message() |> private()
  defp run(["device", identifier], request), do: device(request, identifier)
  defp run(["identify", identifier], request), do: act(request, identifier, "device.identify")
  defp run(["reboot", identifier], request), do: act(request, identifier, "device.reboot")
  defp run(["script", identifier], request), do: scripts(request, identifier)
  defp run(["script", identifier | name], request), do: run_script(request, identifier, Enum.join(name, " "))

  defp run([word | _], request) do
    help(request, "`#{Actions.escape(word)}` is not something `#{request.command}` does.")
  end

  defp help(request, preface \\ nil) do
    command = request.command

    text =
      Enum.join(
        Enum.reject(
          [
            preface,
            "`#{command} device <identifier>` shows a device's state.",
            "`#{command} identify <identifier>` and `#{command} reboot <identifier>` ask a device to identify itself or reboot.",
            "`#{command} script <identifier>` lists the support scripts for its product, and `#{command} script <identifier> <name>` runs one.",
            "`#{command} link` links your #{Actions.platform()} account, which everything else is done as."
          ],
          &is_nil/1
        ),
        "\n"
      )

    private(text)
  end

  ## device

  defp device(request, identifier), do: DeviceCards.show(request.team_id, request.slack_user_id, identifier)

  ## identify and reboot

  defp act(request, identifier, action) do
    {verb, permission} =
      case action do
        "device.reboot" -> {"reboot", :"device:reboot"}
        "device.identify" -> {"identify itself", :"device:identify"}
      end

    with {:ok, user, device} <-
           Actions.authorize(
             request.team_id,
             request.slack_user_id,
             identifier,
             permission,
             "ask a device to #{verb}"
           ),
         true <- Tracker.online?(device) || {:offline, device},
         :ok <- Actions.not_just_rebooted(action, device, user) do
      via = Actions.via(request)
      name = Actions.escape(user.name)
      identifier = Actions.escape(device.identifier)

      text =
        case action do
          "device.reboot" ->
            {:ok, _} = DeviceEvents.reboot(device, user, via: via)
            ":arrows_counterclockwise: #{name} rebooted *#{identifier}* from Slack."

          "device.identify" ->
            {:ok, _} = DeviceEvents.identify(device, user, via: via)
            ":mag: #{name} asked *#{identifier}* to identify itself, from Slack."
        end

      %{response_type: "in_channel", text: text}
    else
      {:offline, device} -> private(Actions.offline_message(device, verb))
      {:error, _reason, message} -> private(message)
    end
  end

  ## scripts

  defp scripts(request, identifier) do
    case Actions.authorize(
           request.team_id,
           request.slack_user_id,
           identifier,
           :"support_script:run",
           "run support scripts"
         ) do
      {:ok, _user, device} ->
        %{product: product} = device = Repo.preload(device, :product)
        product_name = Actions.escape(product.name)

        case Scripts.all_by_product(product) do
          [] ->
            private("#{product_name} has no support scripts.")

          scripts ->
            names = Enum.map_join(scripts, "\n", &"• `#{Actions.escape(&1.name)}`")

            private(
              "Support scripts for #{product_name}:\n#{names}\nRun one with `#{request.command} script #{Actions.escape(device.identifier)} <name>`."
            )
        end

      {:error, _reason, message} ->
        private(message)
    end
  end

  defp run_script(request, identifier, name) do
    with {:ok, user, device} <-
           Actions.authorize(
             request.team_id,
             request.slack_user_id,
             identifier,
             :"support_script:run",
             "run support scripts"
           ),
         device = Repo.preload(device, :product),
         {:script, {:ok, script}} <- {:script, Scripts.get_by_product_and_name_with_id_fallback(device.product, name)},
         true <- Tracker.online?(device) || {:offline, device} do
      {:ok, _pid} =
        Task.Supervisor.start_child(NervesHub.TaskSupervisor, fn ->
          :ok = ScriptRuns.run(request, user, device, script)
        end)

      private("Running `#{Actions.escape(script.name)}` on *#{Actions.escape(device.identifier)}*...")
    else
      {:script, {:error, :not_found}} ->
        private(
          "There is no support script called `#{Actions.escape(name)}` for that device's product. `#{request.command} script #{Actions.escape(identifier)}` lists them."
        )

      {:offline, device} ->
        private(Actions.offline_message(device, "run a script"))

      {:error, _reason, message} ->
        private(message)
    end
  end

  defp private(text) when is_binary(text), do: %{response_type: "ephemeral", text: text}
  defp private(%{} = message), do: Map.put(message, :response_type, "ephemeral")
end
