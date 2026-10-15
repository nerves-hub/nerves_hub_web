defmodule NervesHub.AuditLogs.OrgTemplates do
  @moduledoc """
  Audit log entries for what belongs to an organization rather than to one of
  its products.
  """
  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.User
  alias NervesHub.AuditLogs
  alias NervesHub.Integrations.ChannelEvents
  alias NervesHub.Integrations.Slack.Subscription
  alias NervesHub.Integrations.Slack.Workspace
  alias NervesHub.Integrations.Teams.Channel
  alias NervesHub.Webhooks.Webhook

  # Webhooks are described by their host rather than their URL. Some receivers
  # (chat incoming webhooks, for one) put their credentials in the URL, and the
  # audit log is readable by everyone in the organization.
  @spec audit_webhook_created(User.t(), Org.t(), Webhook.t()) :: :ok
  def audit_webhook_created(user, org, webhook) do
    description =
      "User #{user.name} added webhook #{webhook.id} sending #{Enum.join(webhook.events, ", ")} from #{products(webhook)} to #{webhook_host(webhook)}"

    AuditLogs.audit!(user, org, description)
  end

  @spec audit_webhook_updated(User.t(), Org.t(), Webhook.t()) :: :ok
  def audit_webhook_updated(user, org, webhook) do
    state = if webhook.enabled, do: "on", else: "off"

    description =
      "User #{user.name} updated webhook #{webhook.id} (#{state}) sending #{Enum.join(webhook.events, ", ")} from #{products(webhook)} to #{webhook_host(webhook)}"

    AuditLogs.audit!(user, org, description)
  end

  @spec audit_webhook_deleted(User.t(), Org.t(), Webhook.t()) :: :ok
  def audit_webhook_deleted(user, org, webhook) do
    description = "User #{user.name} removed webhook #{webhook.id} sending to #{webhook_host(webhook)}"

    AuditLogs.audit!(user, org, description)
  end

  @spec audit_webhook_secret_regenerated(User.t(), Org.t(), Webhook.t()) :: :ok
  def audit_webhook_secret_regenerated(user, org, webhook) do
    description = "User #{user.name} regenerated the signing secret of webhook #{webhook.id}"

    AuditLogs.audit!(user, org, description)
  end

  @spec audit_slack_connected(User.t(), Org.t(), Workspace.t()) :: :ok
  def audit_slack_connected(user, org, workspace) do
    description = "User #{user.name} connected Slack workspace #{workspace.team_name} (#{workspace.team_id})"

    AuditLogs.audit!(user, org, description)
  end

  @spec audit_slack_disconnected(User.t(), Org.t(), Workspace.t()) :: :ok
  def audit_slack_disconnected(user, org, workspace) do
    description = "User #{user.name} disconnected Slack workspace #{workspace.team_name} (#{workspace.team_id})"

    AuditLogs.audit!(user, org, description)
  end

  # Slack said so, rather than a member, so the organization is the actor.
  @spec audit_slack_removed(Org.t(), Workspace.t(), String.t()) :: :ok
  def audit_slack_removed(org, workspace, reason) do
    description =
      "Slack workspace #{workspace.team_name} (#{workspace.team_id}) was disconnected because #{reason}"

    AuditLogs.audit!(org, org, description)
  end

  @spec audit_slack_subscription_created(User.t(), Org.t(), Subscription.t()) :: :ok
  def audit_slack_subscription_created(user, org, subscription) do
    description =
      "User #{user.name} started posting #{slack_events(subscription)} from #{products(subscription)} to Slack channel ##{subscription.channel_name} (#{subscription.channel_id})"

    AuditLogs.audit!(user, org, description)
  end

  @spec audit_slack_subscription_updated(User.t(), Org.t(), Subscription.t()) :: :ok
  def audit_slack_subscription_updated(user, org, subscription) do
    state = if subscription.enabled, do: "on", else: "off"

    description =
      "User #{user.name} updated Slack channel ##{subscription.channel_name} (#{state}) to get #{slack_events(subscription)} from #{products(subscription)}"

    AuditLogs.audit!(user, org, description)
  end

  @spec audit_slack_subscription_deleted(User.t(), Org.t(), Subscription.t()) :: :ok
  def audit_slack_subscription_deleted(user, org, subscription) do
    description = "User #{user.name} stopped posting to Slack channel ##{subscription.channel_name}"

    AuditLogs.audit!(user, org, description)
  end

  @spec audit_teams_channel_created(User.t(), Org.t(), Channel.t()) :: :ok
  def audit_teams_channel_created(user, org, channel) do
    description =
      "User #{user.name} started posting #{channel_events(channel)} from #{products(channel)} to Teams channel #{channel.name} (a Workflows webhook on #{channel.url_host})"

    AuditLogs.audit!(user, org, description)
  end

  @doc """
  `url_changed?` says the channel was pointed at another Workflows webhook,
  whose URL is not recorded: it is what lets anyone post to the channel.
  """
  @spec audit_teams_channel_updated(User.t(), Org.t(), Channel.t(), boolean()) :: :ok
  def audit_teams_channel_updated(user, org, channel, url_changed?) do
    state = if channel.enabled, do: "on", else: "off"
    url = if url_changed?, do: ", with a new Workflows webhook on #{channel.url_host},", else: ""

    description =
      "User #{user.name} updated Teams channel #{channel.name} (#{state})#{url} to get #{channel_events(channel)} from #{products(channel)}"

    AuditLogs.audit!(user, org, description)
  end

  @spec audit_teams_channel_deleted(User.t(), Org.t(), Channel.t()) :: :ok
  def audit_teams_channel_deleted(user, org, channel) do
    description = "User #{user.name} stopped posting to Teams channel #{channel.name}"

    AuditLogs.audit!(user, org, description)
  end

  defp slack_events(%Subscription{events: events}), do: Enum.map_join(events, ", ", &ChannelEvents.label/1)
  defp channel_events(%Channel{events: events}), do: Enum.map_join(events, ", ", &ChannelEvents.label/1)

  defp webhook_host(%Webhook{url: url}), do: URI.parse(url).host

  defp products(%{all_products: true}), do: "every product"

  defp products(%{products: products}) do
    "#{if length(products) == 1, do: "product", else: "products"} #{Enum.map_join(products, ", ", & &1.name)}"
  end
end
