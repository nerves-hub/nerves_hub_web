defmodule NervesHubWeb.Integrations.Slack.Unfurls do
  @moduledoc """
  Previews of NervesHub links posted in Slack: a device's card, or a
  deployment group's release and workflow, under the message that links it.

  Slack sends `link_shared` (`NervesHubWeb.Integrations.Slack.EventsController`) when
  somebody posts, or is typing, a link to a domain the Slack app registered.
  NervesHub answers with `chat.unfurl`. Only links to this instance's own
  host, and to a device's or a deployment group's pages, are previewed, at
  most five a message.

  ## Who a preview is checked against

  Everyone in the conversation sees a preview, but Slack only says who
  posted the link, so the preview is checked against them, as Share in
  channel is: posting a link is sharing what it shows. Their linked
  NervesHub user must be a member of the organization the link points into,
  that organization must be connected to the workspace, and their role there
  must let them see the page (`NervesHubWeb.Integrations.Slack.Actions.authorize_in/6`).

  A link the poster may not see is left without a preview, without saying
  why: the preview would be seen by everyone, and so would the reason. A
  poster who has not linked their account is asked to, privately, through
  Slack's `user_auth_required`, and nobody sees a preview.

  A preview has no buttons. It sits under somebody else's message, and the
  link it previews is a click away.
  """

  alias NervesHub.Accounts
  alias NervesHub.Accounts.Scope
  alias NervesHub.Accounts.User
  alias NervesHub.Devices
  alias NervesHub.Devices.Device
  alias NervesHub.Integrations.Slack.Client
  alias NervesHub.Integrations.Slack.Users
  alias NervesHub.Integrations.Slack.Workspace
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.DeploymentWorkflowStep
  alias NervesHub.Products
  alias NervesHub.Repo
  alias NervesHubWeb.Integrations.Slack.Actions
  alias NervesHubWeb.Integrations.Slack.DeviceCards

  require Logger

  @max_links 5

  @typedoc "A NervesHub page a link points at, by the names in its path."
  @type page() ::
          {:device, org_name :: String.t(), product_name :: String.t(), identifier :: String.t()}
          | {:deployment_group, org_name :: String.t(), product_name :: String.t(), name :: String.t()}

  @doc """
  Previews the NervesHub links in a `link_shared` event from the workspace
  `team_id`. Returns what was sent to Slack, for tests: `:unfurled`,
  `:asked_to_link`, or `:nothing` when no link was one to preview or the
  poster may see none of them.
  """
  @spec unfurl(String.t(), map()) :: :unfurled | :asked_to_link | :nothing
  def unfurl(team_id, %{"links" => links, "user" => slack_user_id} = event)
      when is_list(links) and is_binary(slack_user_id) do
    pages =
      links
      |> Enum.flat_map(fn
        %{"url" => url} when is_binary(url) -> [url]
        _ -> []
      end)
      |> Enum.uniq()
      |> Enum.flat_map(fn url ->
        case page(url) do
          nil -> []
          page -> [{url, page}]
        end
      end)
      |> Enum.take(@max_links)

    with [_ | _] <- pages,
         {:ok, message} <- message(event),
         %Workspace{bot_token: token} <- Repo.get_by(Workspace, team_id: team_id) do
      case Users.use_link(team_id, slack_user_id) do
        nil ->
          link = Actions.link_message(team_id, "to see its links previewed here")
          :ok = send_unfurl(token, Map.merge(message, %{user_auth_required: true, user_auth_blocks: link.blocks}))
          :asked_to_link

        %User{} = user ->
          unfurls =
            for {url, page} <- pages, {:ok, preview} <- [preview(team_id, user, page)], into: %{}, do: {url, preview}

          if unfurls == %{} do
            :nothing
          else
            :ok = send_unfurl(token, Map.put(message, :unfurls, unfurls))
            :unfurled
          end
      end
    else
      _ -> :nothing
    end
  end

  def unfurl(_team_id, _event), do: :nothing

  @doc """
  The NervesHub page a URL points at, or `nil` when it is not one of this
  instance's device or deployment group pages. Any of a page's tabs counts.
  """
  @spec page(String.t()) :: page() | nil
  def page(url) do
    with %URI{scheme: scheme, host: host, path: path} when scheme in ["http", "https"] and is_binary(path) <-
           URI.parse(url),
         true <- this_host?(host),
         %{route: route, path_params: params} <- Phoenix.Router.route_info(NervesHubWeb.Router, "GET", path, host) do
      params = decode(params)

      case route do
        "/org/:org_name/:product_name/devices/:device_identifier" <> _ ->
          {:device, params["org_name"], params["product_name"], params["device_identifier"]}

        "/org/:org_name/:product_name/deployment_groups/:name" <> _ ->
          {:deployment_group, params["org_name"], params["product_name"], params["name"]}

        _ ->
          nil
      end
    else
      _ -> nil
    end
  end

  defp this_host?(host) when is_binary(host) do
    String.downcase(host) == String.downcase(URI.parse(NervesHubWeb.Endpoint.url()).host)
  end

  defp this_host?(_host), do: false

  # The router leaves path parameters as they were in the URL.
  defp decode(params), do: Map.new(params, fn {key, value} -> {key, URI.decode(value)} end)

  # Which message to preview the links in. A link being typed is previewed
  # in the composer, by `unfurl_id`, and a posted one either way.
  defp message(%{"unfurl_id" => unfurl_id, "source" => source}) when is_binary(unfurl_id) and is_binary(source),
    do: {:ok, %{unfurl_id: unfurl_id, source: source}}

  defp message(%{"channel" => channel, "message_ts" => ts}) when is_binary(channel) and is_binary(ts),
    do: {:ok, %{channel: channel, ts: ts}}

  defp message(_event), do: :error

  defp preview(team_id, user, {:device, org_name, product_name, identifier}) do
    with {:ok, org} <- Accounts.get_org_by_name(org_name),
         :ok <- Actions.authorize_in(team_id, user, org, :"device:view", "see devices", "the link"),
         {:ok, product} <- Products.get_product_by_org_id_and_name(org.id, product_name),
         {:ok, %Device{deleted_at: nil} = device} <-
           Devices.get_by_identifier(%Scope{org: org, product: product, user: user}, identifier) do
      {:ok, %{blocks: DeviceCards.card(device, buttons: false).blocks}}
    else
      _ -> :error
    end
  end

  defp preview(team_id, user, {:deployment_group, org_name, product_name, name}) do
    with {:ok, org} <- Accounts.get_org_by_name(org_name),
         :ok <- Actions.authorize_in(team_id, user, org, nil, "see deployment groups", "the link"),
         {:ok, product} <- Products.get_product_by_org_id_and_name(org.id, product_name),
         {:ok, deployment_group} <- ManagedDeployments.get_deployment_group_by_name(product, name) do
      {:ok, %{blocks: deployment_group_blocks(deployment_group)}}
    else
      _ -> :error
    end
  end

  defp deployment_group_blocks(deployment_group) do
    release = deployment_group.current_release
    steps = Enum.sort_by(release.steps, & &1.number)

    fields =
      [
        {"Status", if(deployment_group.is_active, do: "Active", else: "Paused")},
        {"Release", release_text(release)},
        {"Workflow", workflow_text(steps)},
        {"Devices", Integer.to_string(deployment_group.device_count || 0)},
        {"Product", Actions.escape(deployment_group.product.name)}
      ]
      |> Enum.reject(fn {_label, value} -> is_nil(value) end)
      |> Enum.map(fn {label, value} -> %{type: "mrkdwn", text: "*#{label}*\n#{value}"} end)

    [
      %{
        type: "section",
        text: %{type: "mrkdwn", text: "*#{Actions.escape(deployment_group.name)}*"},
        fields: fields
      }
    ]
  end

  defp release_text(%{number: number, firmware: %{version: version}}) when is_binary(version),
    do: "#{number}, firmware #{Actions.escape(version)}"

  defp release_text(%{number: number}), do: Integer.to_string(number)

  # Where the workflow stands, as the deployment group's page would show it:
  # a failed step holds it, otherwise the step running, otherwise it has not
  # begun. A release without a workflow has nothing to say.
  defp workflow_text([]), do: nil

  defp workflow_text(steps) do
    of = length(steps)

    with nil <- Enum.find(steps, &(&1.status == :error)),
         nil <- Enum.find(steps, &(&1.status == :in_progress)) do
      "Not started"
    else
      %DeploymentWorkflowStep{status: :error} = step ->
        "#{step_label(step)} failed (step #{step.number} of #{of})"

      %DeploymentWorkflowStep{type: :approval_required, approved_at: nil} = step ->
        "Waiting for approval at #{step_label(step)} (step #{step.number} of #{of})"

      step ->
        "#{step_label(step)} (step #{step.number} of #{of})"
    end
  end

  defp step_label(step), do: Actions.escape(DeploymentWorkflowStep.label(step))

  defp send_unfurl(token, body) do
    case Client.unfurl(token, body) do
      {:ok, _} -> :ok
      {:error, error} -> Logger.warning("Could not preview a NervesHub link in Slack: #{inspect(error)}")
    end

    :ok
  end
end
