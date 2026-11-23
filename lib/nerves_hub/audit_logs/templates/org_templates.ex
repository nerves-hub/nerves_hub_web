defmodule NervesHub.AuditLogs.OrgTemplates do
  @moduledoc """
  Audit log entries for what belongs to an organization rather than to one of
  its products.

  Each description is a `NervesHub.AuditLogs.Template`. Names someone typed
  or another service sent (a channel's, a workspace's, the products a
  subscription covers) go in as values.
  """
  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.User
  alias NervesHub.AuditLogs
  alias NervesHub.AuditLogs.Template
  alias NervesHub.Integrations.ChannelEvents
  alias NervesHub.Integrations.ChatWebhooks
  alias NervesHub.Integrations.ChatWebhooks.ChatWebhook
  alias NervesHub.Integrations.Slack.Subscription
  alias NervesHub.Integrations.Slack.Workspace
  alias NervesHub.Webhooks.Webhook

  # Webhooks are described by their host rather than their URL. Some receivers
  # (chat incoming webhooks, for one) put their credentials in the URL, and the
  # audit log is readable by everyone in the organization.
  @spec audit_webhook_created(User.t(), Org.t(), Webhook.t()) :: :ok
  def audit_webhook_created(user, org, webhook) do
    template =
      Template.new("%{actor} added webhook %{webhook} sending %{events} from %{products} to %{host}",
        webhook: webhook.id,
        events: Enum.join(webhook.events, ", "),
        products: products(webhook),
        host: webhook_host(webhook)
      )

    AuditLogs.audit!(user, org, template)
  end

  @spec audit_webhook_updated(User.t(), Org.t(), Webhook.t()) :: :ok
  def audit_webhook_updated(user, org, webhook) do
    state = if webhook.enabled, do: "on", else: "off"

    template =
      Template.new("%{actor} updated webhook %{webhook} (#{state}) sending %{events} from %{products} to %{host}",
        webhook: webhook.id,
        events: Enum.join(webhook.events, ", "),
        products: products(webhook),
        host: webhook_host(webhook)
      )

    AuditLogs.audit!(user, org, template)
  end

  @spec audit_webhook_deleted(User.t(), Org.t(), Webhook.t()) :: :ok
  def audit_webhook_deleted(user, org, webhook) do
    template =
      Template.new("%{actor} removed webhook %{webhook} sending to %{host}",
        webhook: webhook.id,
        host: webhook_host(webhook)
      )

    AuditLogs.audit!(user, org, template)
  end

  @spec audit_webhook_secret_regenerated(User.t(), Org.t(), Webhook.t()) :: :ok
  def audit_webhook_secret_regenerated(user, org, webhook) do
    template = Template.new("%{actor} regenerated the signing secret of webhook %{webhook}", webhook: webhook.id)

    AuditLogs.audit!(user, org, template)
  end

  @spec audit_two_factor_requirement(User.t(), Org.t()) :: :ok
  def audit_two_factor_requirement(user, %Org{require_two_factor: true} = org) do
    AuditLogs.audit!(user, org, Template.new("%{actor} started requiring two-factor authentication of every member"))
  end

  def audit_two_factor_requirement(user, %Org{require_two_factor: false} = org) do
    AuditLogs.audit!(user, org, Template.new("%{actor} stopped requiring two-factor authentication of members"))
  end

  @spec audit_slack_connected(User.t(), Org.t(), Workspace.t()) :: :ok
  def audit_slack_connected(user, org, workspace) do
    template = Template.new("%{actor} connected Slack workspace %{workspace} (%{team_id})", workspace_values(workspace))

    AuditLogs.audit!(user, org, template)
  end

  @spec audit_slack_disconnected(User.t(), Org.t(), Workspace.t()) :: :ok
  def audit_slack_disconnected(user, org, workspace) do
    template =
      Template.new("%{actor} disconnected Slack workspace %{workspace} (%{team_id})", workspace_values(workspace))

    AuditLogs.audit!(user, org, template)
  end

  # Slack said so, rather than a member, so the organization is the actor.
  @spec audit_slack_removed(Org.t(), Workspace.t(), String.t()) :: :ok
  def audit_slack_removed(org, workspace, reason) do
    template =
      Template.new(
        "Slack workspace %{workspace} (%{team_id}) was disconnected because %{reason}",
        [reason: reason] ++ workspace_values(workspace)
      )

    AuditLogs.audit!(org, org, template)
  end

  @spec audit_slack_subscription_created(User.t(), Org.t(), Subscription.t()) :: :ok
  def audit_slack_subscription_created(user, org, subscription) do
    template =
      Template.new("%{actor} started posting %{events} from %{products} to Slack channel #%{channel} (%{channel_id})",
        events: slack_events(subscription),
        products: products(subscription),
        channel: subscription.channel_name,
        channel_id: subscription.channel_id
      )

    AuditLogs.audit!(user, org, template)
  end

  @spec audit_slack_subscription_updated(User.t(), Org.t(), Subscription.t()) :: :ok
  def audit_slack_subscription_updated(user, org, subscription) do
    state = if subscription.enabled, do: "on", else: "off"

    template =
      Template.new("%{actor} updated Slack channel #%{channel} (#{state}) to get %{events} from %{products}",
        channel: subscription.channel_name,
        events: slack_events(subscription),
        products: products(subscription)
      )

    AuditLogs.audit!(user, org, template)
  end

  @spec audit_slack_subscription_deleted(User.t(), Org.t(), Subscription.t()) :: :ok
  def audit_slack_subscription_deleted(user, org, subscription) do
    template = Template.new("%{actor} stopped posting to Slack channel #%{channel}", channel: subscription.channel_name)

    AuditLogs.audit!(user, org, template)
  end

  @spec audit_chat_webhook_created(User.t(), Org.t(), ChatWebhook.t()) :: :ok
  def audit_chat_webhook_created(user, org, channel) do
    template =
      Template.new(
        "%{actor} started posting %{events} from %{products} to %{service} channel %{channel} (a webhook on %{host})",
        events: channel_events(channel),
        products: products(channel),
        service: service(channel),
        channel: channel.name,
        host: channel.url_host
      )

    AuditLogs.audit!(user, org, template)
  end

  @doc """
  `url_changed?` says the channel was pointed at another webhook, whose URL
  is not recorded: it is what lets anyone post to the channel.
  """
  @spec audit_chat_webhook_updated(User.t(), Org.t(), ChatWebhook.t(), boolean()) :: :ok
  def audit_chat_webhook_updated(user, org, channel, url_changed?) do
    state = if channel.enabled, do: "on", else: "off"
    url = if url_changed?, do: ", with a new webhook on %{host},", else: ""

    template =
      Template.new("%{actor} updated %{service} channel %{channel} (#{state})#{url} to get %{events} from %{products}",
        service: service(channel),
        channel: channel.name,
        host: channel.url_host,
        events: channel_events(channel),
        products: products(channel)
      )

    AuditLogs.audit!(user, org, template)
  end

  @spec audit_chat_webhook_deleted(User.t(), Org.t(), ChatWebhook.t()) :: :ok
  def audit_chat_webhook_deleted(user, org, channel) do
    template =
      Template.new("%{actor} stopped posting to %{service} channel %{channel}",
        service: service(channel),
        channel: channel.name
      )

    AuditLogs.audit!(user, org, template)
  end

  defp workspace_values(%Workspace{} = workspace), do: [workspace: workspace.team_name, team_id: workspace.team_id]

  defp service(%ChatWebhook{provider: provider}), do: ChatWebhooks.provider(provider).label()

  defp slack_events(%Subscription{events: events}), do: Enum.map_join(events, ", ", &ChannelEvents.label/1)
  defp channel_events(%ChatWebhook{events: events}), do: Enum.map_join(events, ", ", &ChannelEvents.label/1)

  defp webhook_host(%Webhook{url: url}), do: URI.parse(url).host

  defp products(%{all_products: true}), do: "every product"

  defp products(%{products: products}) do
    "#{if length(products) == 1, do: "product", else: "products"} #{Enum.map_join(products, ", ", & &1.name)}"
  end
end
