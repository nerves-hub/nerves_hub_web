defmodule NervesHubWeb.Live.Org.Integrations do
  @moduledoc """
  The organization's integrations: where its products' device events go, in
  two tables. Chat channels are the Slack channels of its Slack workspaces,
  when the instance has a Slack app
  (`NervesHubWeb.Live.Org.Integrations.SlackSection`), and its Microsoft
  Teams and Discord channels
  (`NervesHubWeb.Live.Org.Integrations.ChatWebhookSection`). Webhooks are
  its own endpoints, which this page looks after itself. An organization
  with none of either is offered one of each instead.

  This page loads every integration and passes the chat channels to their
  sections. A section that changes one tells the page
  (`:integrations_changed`), which loads them all again, as the count in the
  header, the Add integration menu and the empty state go by them all.

  Members who cannot manage webhooks see each webhook's host, events, products
  and state, but not its URL or signing secret. Some receivers carry
  credentials in the URL itself, so it is treated like the secret.
  """
  use NervesHubWeb, :live_view

  import NervesHubWeb.Live.Org.Integrations.Components

  alias NervesHub.Integrations.ChatWebhooks
  alias NervesHub.Integrations.Slack
  alias NervesHub.Integrations.Slack.Subscriptions
  alias NervesHub.Products
  alias NervesHub.Webhooks
  alias NervesHub.Webhooks.Events
  alias NervesHub.Webhooks.Webhook
  alias NervesHubWeb.Live.Org.Integrations.ChatWebhookSection
  alias NervesHubWeb.Live.Org.Integrations.SlackSection
  alias NervesHubWeb.Mounts.OrgCounts

  on_mount(OrgCounts)

  @webhook_docs "https://github.com/nerves-hub/nerves_hub_web/blob/main/docs/webhooks.md"

  @decorate requires_permission(:"organization:view")
  def mount(_params, _session, %{assigns: %{current_scope: scope}} = socket) do
    socket
    |> page_title("Integrations - #{scope.org.name}")
    |> sidebar_tab(:integrations)
    |> assign(:org, scope.org)
    |> assign(:products, Products.get_products(scope))
    |> assign(:event_columns, webhook_event_columns())
    |> assign(:testing, MapSet.new())
    |> assign(:slack_configured?, Slack.configured?())
    |> assign(:webhook_docs, @webhook_docs)
    |> close_form()
    |> assign_integrations()
    |> ok()
  end

  # From the Slack, Teams and Discord sections, whose own flash would not be shown.
  def handle_info({:put_flash, kind, message}, socket) do
    socket
    |> put_flash(kind, message)
    |> noreply()
  end

  def handle_info(:integrations_changed, socket) do
    socket
    |> assign_integrations()
    |> noreply()
  end

  @decorate requires_permission(:"webhook:create")
  def handle_event("new", _params, socket) do
    authorized!(:"webhook:create", socket.assigns.current_scope)

    socket
    |> assign(:editing, :new)
    |> assign(:form, to_form(Webhooks.change_webhook(socket.assigns.org, %Webhook{products: []})))
    |> noreply()
  end

  @decorate requires_permission(:"webhook:update")
  def handle_event("edit", %{"webhook_id" => id}, socket) do
    authorized!(:"webhook:update", socket.assigns.current_scope)

    webhook = Webhooks.get_webhook!(socket.assigns.org, id)

    socket
    |> assign(:editing, webhook)
    |> assign(:form, to_form(Webhooks.change_webhook(socket.assigns.org, webhook)))
    |> noreply()
  end

  @decorate requires_permission(:"organization:view")
  def handle_event("cancel", _params, socket) do
    socket
    |> close_form()
    |> noreply()
  end

  @decorate requires_permission(:"organization:view")
  def handle_event("validate", %{"webhook" => params}, socket) do
    changeset =
      socket.assigns.org
      |> Webhooks.change_webhook(form_subject(socket.assigns.editing), form_params(params))
      |> Map.put(:action, :validate)

    socket
    |> assign(:form, to_form(changeset))
    |> noreply()
  end

  @decorate authorizes_in_body()
  def handle_event("save", %{"webhook" => params}, socket) do
    %{current_scope: scope, editing: editing} = socket.assigns

    permission = if(editing == :new, do: :"webhook:create", else: :"webhook:update")
    socket = authorize!(socket, permission, scope.org)

    params = form_params(params)

    result =
      case editing do
        :new -> Webhooks.create_webhook(scope, params)
        %Webhook{} = webhook -> Webhooks.update_webhook(scope, webhook, params)
      end

    case result do
      {:ok, _webhook} ->
        socket
        |> close_form()
        |> assign_integrations()
        |> put_flash(:info, if(editing == :new, do: "The webhook was added.", else: "The webhook was updated."))
        |> noreply()

      {:error, %Ecto.Changeset{} = changeset} ->
        socket
        |> assign(:form, to_form(changeset))
        |> noreply()

      {:error, :too_many_webhooks} ->
        socket
        |> close_form()
        |> put_flash(:error, "An organization can have at most #{Webhooks.max_webhooks_per_org()} webhooks.")
        |> noreply()
    end
  end

  @decorate requires_permission(:"webhook:update")
  def handle_event("toggle", %{"webhook_id" => id}, socket) do
    authorized!(:"webhook:update", socket.assigns.current_scope)

    webhook = Webhooks.get_webhook!(socket.assigns.org, id)

    case Webhooks.update_webhook(socket.assigns.current_scope, webhook, %{enabled: !webhook.enabled}) do
      {:ok, updated} ->
        socket
        |> assign_integrations()
        |> put_flash(:info, "Deliveries to #{host(updated)} are #{if updated.enabled, do: "on", else: "off"}.")
        |> noreply()

      {:error, _changeset} ->
        socket
        |> put_flash(:error, "The webhook could not be changed. Edit it to see what needs fixing.")
        |> noreply()
    end
  end

  @decorate requires_permission(:"webhook:update")
  def handle_event("regenerate-secret", %{"webhook_id" => id}, socket) do
    authorized!(:"webhook:update", socket.assigns.current_scope)

    webhook = Webhooks.get_webhook!(socket.assigns.org, id)
    {:ok, _webhook} = Webhooks.regenerate_secret(socket.assigns.current_scope, webhook)

    socket
    |> assign_integrations()
    |> put_flash(:info, "A new signing secret was generated. Deliveries are signed with it from now on.")
    |> noreply()
  end

  @decorate requires_permission(:"webhook:delete")
  def handle_event("delete", %{"webhook_id" => id}, socket) do
    authorized!(:"webhook:delete", socket.assigns.current_scope)

    webhook = Webhooks.get_webhook!(socket.assigns.org, id)
    {:ok, _webhook} = Webhooks.delete_webhook(socket.assigns.current_scope, webhook)

    socket
    |> close_form()
    |> assign_integrations()
    |> put_flash(:info, "The webhook to #{host(webhook)} was removed.")
    |> noreply()
  end

  # The request runs off the LiveView process: an endpoint that does not
  # answer would otherwise freeze the page for the whole timeout.
  @decorate requires_permission(:"webhook:update")
  def handle_event("send-test", %{"webhook_id" => id}, socket) do
    authorized!(:"webhook:update", socket.assigns.current_scope)

    webhook = Webhooks.get_webhook!(socket.assigns.org, id)
    scope = socket.assigns.current_scope

    socket
    |> update(:testing, &MapSet.put(&1, webhook.id))
    |> start_async({:send_test, webhook.id}, fn -> {host(webhook), Webhooks.send_test_event(scope, webhook)} end)
    |> noreply()
  end

  def handle_async({:send_test, webhook_id}, result, socket) do
    socket = update(socket, :testing, &MapSet.delete(&1, webhook_id))

    case result do
      {:ok, {host, {:ok, status}}} ->
        put_flash(socket, :info, "The test event was delivered to #{host}, which answered HTTP #{status}.")

      {:ok, {host, {:error, _status, message}}} ->
        put_flash(socket, :error, "The test event to #{host} failed: #{message}")

      {:exit, _reason} ->
        put_flash(socket, :error, "The test event could not be sent.")
    end
    |> noreply()
  end

  # Every integration, and what the page works out from them: how many there
  # are, whether the chat channels table has anything to show, and whether
  # there is nothing at all, which shows the empty state instead.
  defp assign_integrations(socket) do
    org = socket.assigns.org
    connections = if socket.assigns.slack_configured?, do: Slack.list_connections(org), else: []
    teams = ChatWebhooks.list_channels(org, :teams)
    discord = ChatWebhooks.list_channels(org, :discord)
    webhooks = Webhooks.list_webhooks(org)

    subscriptions = Enum.sum_by(connections, &length(&1.subscriptions))
    chat_count = subscriptions + length(teams) + length(discord)

    socket
    |> assign(:slack_connections, connections)
    |> assign(:slack_subscription_count, subscriptions)
    |> assign(:teams_channels, teams)
    |> assign(:discord_channels, discord)
    |> assign(:webhooks, webhooks)
    |> assign(:chat_count, chat_count)
    |> assign(:count, chat_count + length(webhooks))
    |> assign(:chat_table?, chat_count > 0 || connections != [])
    |> assign(:empty?, chat_count == 0 && connections == [] && webhooks == [])
  end

  defp close_form(socket) do
    socket
    |> assign(:editing, nil)
    |> assign(:form, nil)
  end

  defp form_subject(:new), do: %Webhook{products: []}
  defp form_subject(%Webhook{} = webhook), do: webhook

  defp host(%Webhook{url: url}), do: URI.parse(url).host

  defp webhook_name(%Webhook{description: description} = webhook) when description in [nil, ""], do: host(webhook)
  defp webhook_name(%Webhook{description: description}), do: description

  defp status(%Webhook{enabled: false}), do: :off
  defp status(%Webhook{failing_since: %DateTime{}}), do: :failing
  defp status(%Webhook{}), do: :on

  defp event_labels(webhook), do: Enum.map(webhook.events, &Events.label/1)

  defp channels(assigns, :teams), do: assigns.teams_channels
  defp channels(assigns, :discord), do: assigns.discord_channels

  # Why an Add integration item cannot be used, under its name, or nil when
  # it can.
  defp limit_detail(count, max) when count >= max, do: "This organization has #{max}, the most it can have"
  defp limit_detail(_count, _max), do: nil

  defp slack_detail(assigns, connection) do
    limit_detail(assigns.slack_subscription_count, Subscriptions.max_subscriptions_per_org()) ||
      "In the #{connection.workspace.team_name} workspace"
  end

  defp can_add?(assigns, :slack),
    do:
      authorized?(:"slack_subscription:create", assigns.current_scope) &&
        assigns.slack_subscription_count < Subscriptions.max_subscriptions_per_org()

  defp can_add?(assigns, :webhook),
    do:
      authorized?(:"webhook:create", assigns.current_scope) &&
        length(assigns.webhooks) < Webhooks.max_webhooks_per_org()

  defp can_add?(assigns, provider),
    do:
      authorized?(:"chat_webhook:create", assigns.current_scope) &&
        length(channels(assigns, provider)) < ChatWebhooks.max_channels_per_org()

  # A viewer can add nothing, so the Add integration button is turned off
  # rather than opening a menu of items they cannot use.
  defp can_add_any?(assigns) do
    Enum.any?([:slack, :teams, :discord, :webhook], &can_add?(assigns, &1)) ||
      (assigns.slack_configured? && authorized?(:"slack_connection:create", assigns.current_scope))
  end
end
