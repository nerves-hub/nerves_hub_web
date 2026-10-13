defmodule NervesHubWeb.Live.Org.Integrations do
  @moduledoc """
  The organization's integrations: the Slack workspaces it is connected to,
  when the instance has a Slack app, and its webhooks, which say where its
  products' device events are sent, which events, from which products, and
  how each endpoint is doing.

  Members who cannot manage webhooks see each webhook's host, events, products
  and state, but not its URL or signing secret. Some receivers carry
  credentials in the URL itself, so it is treated like the secret.
  """
  use NervesHubWeb, :live_view

  alias NervesHub.Integrations.Slack
  alias NervesHub.Products
  alias NervesHub.Webhooks
  alias NervesHub.Webhooks.Events
  alias NervesHub.Webhooks.Webhook
  alias Phoenix.HTML.Form

  def mount(_params, _session, %{assigns: %{current_scope: scope}} = socket) do
    socket
    |> page_title("Integrations - #{scope.org.name}")
    |> sidebar_tab(:integrations)
    |> assign(:org, scope.org)
    |> assign(:products, Products.get_products(scope))
    |> assign(:event_groups, Events.grouped())
    |> assign(:testing, MapSet.new())
    |> assign(:slack_configured?, Slack.configured?())
    |> close_form()
    |> assign_webhooks()
    |> assign_slack_connections()
    |> ok()
  end

  def handle_event("disconnect-slack", %{"connection_id" => id}, socket) do
    authorized!(:"slack_connection:delete", socket.assigns.current_scope)

    connection = Slack.get_connection!(socket.assigns.org, id)
    :ok = Slack.disconnect(socket.assigns.current_scope, connection)

    socket
    |> assign_slack_connections()
    |> put_flash(:info, "Disconnected the #{connection.workspace.team_name} Slack workspace.")
    |> noreply()
  end

  def handle_event("new", _params, socket) do
    authorized!(:"webhook:create", socket.assigns.current_scope)

    socket
    |> assign(:editing, :new)
    |> assign(:form, to_form(Webhooks.change_webhook(socket.assigns.org, %Webhook{products: []})))
    |> noreply()
  end

  def handle_event("edit", %{"webhook_id" => id}, socket) do
    authorized!(:"webhook:update", socket.assigns.current_scope)

    webhook = Webhooks.get_webhook!(socket.assigns.org, id)

    socket
    |> assign(:editing, webhook)
    |> assign(:form, to_form(Webhooks.change_webhook(socket.assigns.org, webhook)))
    |> noreply()
  end

  def handle_event("cancel", _params, socket) do
    socket
    |> close_form()
    |> noreply()
  end

  def handle_event("validate", %{"webhook" => params}, socket) do
    changeset =
      socket.assigns.org
      |> Webhooks.change_webhook(form_subject(socket.assigns.editing), webhook_params(params))
      |> Map.put(:action, :validate)

    socket
    |> assign(:form, to_form(changeset))
    |> noreply()
  end

  def handle_event("save", %{"webhook" => params}, socket) do
    %{current_scope: scope, editing: editing} = socket.assigns

    authorized!(if(editing == :new, do: :"webhook:create", else: :"webhook:update"), scope)

    params = webhook_params(params)

    result =
      case editing do
        :new -> Webhooks.create_webhook(scope, params)
        %Webhook{} = webhook -> Webhooks.update_webhook(scope, webhook, params)
      end

    case result do
      {:ok, _webhook} ->
        socket
        |> close_form()
        |> assign_webhooks()
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

  def handle_event("toggle", %{"webhook_id" => id}, socket) do
    authorized!(:"webhook:update", socket.assigns.current_scope)

    webhook = Webhooks.get_webhook!(socket.assigns.org, id)

    case Webhooks.update_webhook(socket.assigns.current_scope, webhook, %{enabled: !webhook.enabled}) do
      {:ok, updated} ->
        socket
        |> assign_webhooks()
        |> put_flash(:info, "Deliveries to #{host(updated)} are #{if updated.enabled, do: "on", else: "off"}.")
        |> noreply()

      {:error, _changeset} ->
        socket
        |> put_flash(:error, "The webhook could not be changed. Edit it to see what needs fixing.")
        |> noreply()
    end
  end

  def handle_event("regenerate-secret", %{"webhook_id" => id}, socket) do
    authorized!(:"webhook:update", socket.assigns.current_scope)

    webhook = Webhooks.get_webhook!(socket.assigns.org, id)
    {:ok, _webhook} = Webhooks.regenerate_secret(socket.assigns.current_scope, webhook)

    socket
    |> assign_webhooks()
    |> put_flash(:info, "A new signing secret was generated. Deliveries are signed with it from now on.")
    |> noreply()
  end

  def handle_event("delete", %{"webhook_id" => id}, socket) do
    authorized!(:"webhook:delete", socket.assigns.current_scope)

    webhook = Webhooks.get_webhook!(socket.assigns.org, id)
    {:ok, _webhook} = Webhooks.delete_webhook(socket.assigns.current_scope, webhook)

    socket
    |> close_form()
    |> assign_webhooks()
    |> put_flash(:info, "The webhook to #{host(webhook)} was removed.")
    |> noreply()
  end

  # The request runs off the LiveView process: an endpoint that does not
  # answer would otherwise freeze the page for the whole timeout.
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

  defp assign_slack_connections(%{assigns: %{slack_configured?: false}} = socket) do
    assign(socket, :slack_connections, [])
  end

  defp assign_slack_connections(socket) do
    assign(socket, :slack_connections, Slack.list_connections(socket.assigns.org))
  end

  defp assign_webhooks(socket) do
    assign(socket, :webhooks, Webhooks.list_webhooks(socket.assigns.org))
  end

  defp close_form(socket) do
    socket
    |> assign(:editing, nil)
    |> assign(:form, nil)
  end

  defp form_subject(:new), do: %Webhook{products: []}
  defp form_subject(%Webhook{} = webhook), do: webhook

  # The event and product checkboxes post a blank alongside the checked boxes,
  # so that unticking every box still sends the field and the changeset can
  # say one is needed. The blank is not an event or a product.
  defp webhook_params(params) do
    params
    |> Map.update("events", [], &drop_blank/1)
    |> Map.update("products", [], &drop_blank/1)
  end

  defp drop_blank(values), do: Enum.reject(List.wrap(values), &(&1 == ""))

  defp host(%Webhook{url: url}), do: URI.parse(url).host

  defp selected_events(form) do
    form[:events].value || []
  end

  defp all_products?(form) do
    Form.normalize_value("checkbox", form[:all_products].value)
  end

  # The products the form has ticked, by name, as the changeset holds them:
  # products, or changesets for them once put on the webhook.
  defp selected_products(form) do
    form.source
    |> Ecto.Changeset.get_field(:products, [])
    |> MapSet.new(& &1.name)
  end

  # Held back until somebody has ticked a box or submitted, the way `.input`
  # holds back its own errors, so the form does not open by complaining.
  defp checkbox_errors(form, field) do
    if Phoenix.Component.used_input?(form[field]) do
      Enum.map(form[field].errors, &translate_error/1)
    else
      []
    end
  end

  defp scope_label(%Webhook{all_products: true}), do: "Every product"
  defp scope_label(%Webhook{products: []}), do: "No products"
  defp scope_label(%Webhook{products: products}), do: Enum.map_join(products, ", ", & &1.name)

  # A webhook's Edit, Turn off and Delete sit behind a "more" menu, the way the
  # device page's update-mode menu works.
  defp toggle_menu(webhook_id) do
    JS.toggle(
      to: "#webhook-#{webhook_id}-menu",
      in: {"ease-out duration-150", "opacity-0", "opacity-100"},
      out: {"ease-out duration-150", "opacity-100", "opacity-0"}
    )
  end

  # Only ever closes, so Escape and click-away cannot open it the way
  # `JS.toggle` would.
  defp hide_menu(js \\ %JS{}, webhook_id) do
    JS.hide(js,
      to: "#webhook-#{webhook_id}-menu",
      transition: {"ease-out duration-150", "opacity-100", "opacity-0"}
    )
  end

  attr(:webhook, Webhook, required: true)

  defp status_badge(assigns) do
    ~H"""
    <span
      :if={!@webhook.enabled}
      class="rounded-full border border-base-600 bg-base-800 px-2 py-0.5 text-xs font-medium text-base-400"
    >
      Off
    </span>
    <span
      :if={@webhook.enabled && @webhook.failing_since}
      class="rounded-full border border-alert bg-alert-soft px-2 py-0.5 text-xs font-medium text-alert"
    >
      Failing
    </span>
    <span
      :if={@webhook.enabled && is_nil(@webhook.failing_since)}
      class="rounded-full border border-success px-2 py-0.5 text-xs font-medium text-success"
    >
      On
    </span>
    """
  end
end
