defmodule NervesHubWeb.Live.Product.Integrations do
  @moduledoc """
  The product settings tab for webhooks: where a product's device events are
  sent, which ones, and how each endpoint is doing.

  Members who cannot change the product see each webhook's host, events and
  state, but not its URL or signing secret. Some receivers carry credentials
  in the URL itself, so it is treated like the secret.
  """
  use NervesHubWeb, :live_view

  alias NervesHub.Webhooks
  alias NervesHub.Webhooks.Events
  alias NervesHub.Webhooks.Webhook

  def mount(_params, _session, socket) do
    product = socket.assigns.current_scope.product

    socket
    |> assign(:page_title, "#{product.name} Integrations")
    |> sidebar_tab(:settings)
    |> assign(:tab, :integrations)
    |> assign(:product, product)
    |> assign(:event_groups, Events.grouped())
    |> assign(:testing, MapSet.new())
    |> close_form()
    |> assign_webhooks()
    |> ok()
  end

  def handle_event("new", _params, socket) do
    authorized!(:"product:update", socket.assigns.current_scope)

    socket
    |> assign(:editing, :new)
    |> assign(:form, to_form(Webhooks.change_webhook(%Webhook{})))
    |> noreply()
  end

  def handle_event("edit", %{"webhook_id" => id}, socket) do
    authorized!(:"product:update", socket.assigns.current_scope)

    webhook = Webhooks.get_webhook!(socket.assigns.product, id)

    socket
    |> assign(:editing, webhook)
    |> assign(:form, to_form(Webhooks.change_webhook(webhook)))
    |> noreply()
  end

  def handle_event("cancel", _params, socket) do
    socket
    |> close_form()
    |> noreply()
  end

  def handle_event("validate", %{"webhook" => params}, socket) do
    changeset =
      socket.assigns.editing
      |> form_subject()
      |> Webhooks.change_webhook(webhook_params(params))
      |> Map.put(:action, :validate)

    socket
    |> assign(:form, to_form(changeset))
    |> noreply()
  end

  def handle_event("save", %{"webhook" => params}, socket) do
    authorized!(:"product:update", socket.assigns.current_scope)

    %{current_scope: scope, editing: editing} = socket.assigns
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
        |> put_flash(:error, "A product can have at most #{Webhooks.max_webhooks_per_product()} webhooks.")
        |> noreply()
    end
  end

  def handle_event("toggle", %{"webhook_id" => id}, socket) do
    authorized!(:"product:update", socket.assigns.current_scope)

    webhook = Webhooks.get_webhook!(socket.assigns.product, id)

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
    authorized!(:"product:update", socket.assigns.current_scope)

    webhook = Webhooks.get_webhook!(socket.assigns.product, id)
    {:ok, _webhook} = Webhooks.regenerate_secret(socket.assigns.current_scope, webhook)

    socket
    |> assign_webhooks()
    |> put_flash(:info, "A new signing secret was generated. Deliveries are signed with it from now on.")
    |> noreply()
  end

  def handle_event("delete", %{"webhook_id" => id}, socket) do
    authorized!(:"product:update", socket.assigns.current_scope)

    webhook = Webhooks.get_webhook!(socket.assigns.product, id)
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
    authorized!(:"product:update", socket.assigns.current_scope)

    webhook = Webhooks.get_webhook!(socket.assigns.product, id)
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

  defp assign_webhooks(socket) do
    assign(socket, :webhooks, Webhooks.list_webhooks(socket.assigns.product))
  end

  defp close_form(socket) do
    socket
    |> assign(:editing, nil)
    |> assign(:form, nil)
  end

  defp form_subject(:new), do: %Webhook{}
  defp form_subject(%Webhook{} = webhook), do: webhook

  # The event checkboxes post a blank alongside the checked boxes, so that
  # unticking every box still sends `events` and the changeset can say one is
  # needed. The blank is not an event.
  defp webhook_params(params) do
    Map.update(params, "events", [], fn events -> Enum.reject(List.wrap(events), &(&1 == "")) end)
  end

  defp host(%Webhook{url: url}), do: URI.parse(url).host

  defp selected_events(form) do
    form[:events].value || []
  end

  # Held back until somebody has ticked a box or submitted, the way `.input`
  # holds back its own errors, so the form does not open by complaining.
  defp events_errors(form) do
    if Phoenix.Component.used_input?(form[:events]) do
      Enum.map(form[:events].errors, &translate_error/1)
    else
      []
    end
  end

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
