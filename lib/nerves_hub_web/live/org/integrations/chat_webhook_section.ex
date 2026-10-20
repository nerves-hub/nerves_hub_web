defmodule NervesHubWeb.Live.Org.Integrations.ChatWebhookSection do
  @moduledoc """
  A chat service's card on the organization's Integrations page: the
  Microsoft Teams or Discord channels (`provider`) its device events are
  posted to, each through a webhook made in that channel
  (`NervesHub.Integrations.ChatWebhooks`).

  Adding, changing and removing a channel takes the manage role, as webhooks
  and Slack channels do. Everyone in the organization sees each channel's
  name, events, products and state, and the host its webhook is on, but
  nobody sees the webhook's URL once it is saved: it is all it takes to post
  to the channel. Editing a channel leaves the URL as it was unless a new
  one is pasted in.

  Flash messages go to the parent LiveView (`{:put_flash, kind, message}`):
  a component's own flash is only shown when it navigates.
  """
  use NervesHubWeb, :live_component

  alias NervesHub.Integrations.ChannelEvents
  alias NervesHub.Integrations.ChatWebhooks
  alias NervesHub.Integrations.ChatWebhooks.ChatWebhook
  alias Phoenix.HTML.Form
  alias Phoenix.LiveView.JS

  @impl Phoenix.LiveComponent
  def mount(socket) do
    socket
    |> assign(:events, ChannelEvents.all())
    |> assign(:testing, MapSet.new())
    |> close_form()
    |> ok()
  end

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    socket
    |> assign(assigns)
    |> assign_channels()
    |> ok()
  end

  @impl Phoenix.LiveComponent
  def handle_event("new-channel", _params, socket) do
    authorized!(:"chat_webhook:create", socket.assigns.current_scope)

    socket
    |> assign(:editing, :new)
    |> assign(:form, form(socket, ChatWebhooks.change_channel(socket.assigns.org, new_channel(socket))))
    |> noreply()
  end

  def handle_event("edit-channel", %{"channel_id" => id}, socket) do
    authorized!(:"chat_webhook:update", socket.assigns.current_scope)

    channel = ChatWebhooks.get_channel!(socket.assigns.org, id)

    socket
    |> assign(:editing, channel)
    |> assign(:form, form(socket, ChatWebhooks.change_channel(socket.assigns.org, channel)))
    |> noreply()
  end

  def handle_event("cancel", _params, socket) do
    socket
    |> close_form()
    |> noreply()
  end

  def handle_event("validate", params, socket) do
    params = channel_params(socket, params)

    changeset =
      socket.assigns.org
      |> ChatWebhooks.change_channel(form_subject(socket), form_params(params))
      |> Map.put(:action, :validate)

    socket
    |> assign(:form, form(socket, changeset))
    |> noreply()
  end

  def handle_event("save", params, socket) do
    params = socket |> channel_params(params) |> form_params()

    case socket.assigns.editing do
      :new ->
        authorized!(:"chat_webhook:create", socket.assigns.current_scope)

        socket.assigns.current_scope
        |> ChatWebhooks.create_channel(socket.assigns.provider, params)
        |> saved(socket, fn channel ->
          "#{NervesHub.Branding.friendly_platform_name()} will post to #{channel.name}."
        end)

      %ChatWebhook{} = channel ->
        authorized!(:"chat_webhook:update", socket.assigns.current_scope)

        socket.assigns.current_scope
        |> ChatWebhooks.update_channel(channel, params)
        |> saved(socket, fn _channel -> "The channel was updated." end)
    end
  end

  def handle_event("toggle", %{"channel_id" => id}, socket) do
    authorized!(:"chat_webhook:update", socket.assigns.current_scope)

    channel = ChatWebhooks.get_channel!(socket.assigns.org, id)

    case ChatWebhooks.update_channel(socket.assigns.current_scope, channel, %{"enabled" => !channel.enabled}) do
      {:ok, updated} ->
        socket
        |> assign_channels()
        |> flash(:info, "Posting to #{updated.name} is #{if updated.enabled, do: "on", else: "off"}.")
        |> noreply()

      {:error, _changeset} ->
        socket
        |> flash(:error, "The channel could not be changed. Edit it to see what needs fixing.")
        |> noreply()
    end
  end

  def handle_event("delete", %{"channel_id" => id}, socket) do
    authorized!(:"chat_webhook:delete", socket.assigns.current_scope)

    channel = ChatWebhooks.get_channel!(socket.assigns.org, id)
    {:ok, _} = ChatWebhooks.delete_channel(socket.assigns.current_scope, channel)

    socket
    |> close_form()
    |> assign_channels()
    |> flash(:info, "#{NervesHub.Branding.friendly_platform_name()} stopped posting to #{channel.name}.")
    |> noreply()
  end

  # Off the LiveView process: a chat service not answering would otherwise freeze the
  # page for the whole timeout.
  def handle_event("send-test", %{"channel_id" => id}, socket) do
    authorized!(:"chat_webhook:update", socket.assigns.current_scope)

    channel = ChatWebhooks.get_channel!(socket.assigns.org, id)
    scope = socket.assigns.current_scope

    socket
    |> update(:testing, &MapSet.put(&1, channel.id))
    |> start_async({:send_test, channel.id}, fn -> {channel.name, ChatWebhooks.send_test_message(scope, channel)} end)
    |> noreply()
  end

  @impl Phoenix.LiveComponent
  def handle_async({:send_test, id}, result, socket) do
    socket = update(socket, :testing, &MapSet.delete(&1, id))

    case result do
      {:ok, {name, :ok}} ->
        flash(socket, :info, "Posted a test message to #{name}.")

      {:ok, {name, {:error, error}}} ->
        flash(
          socket,
          :error,
          "#{service_name(socket.assigns.provider)} refused the test message to #{name}: #{error_message(socket.assigns.provider, error)}"
        )

      {:exit, _reason} ->
        flash(socket, :error, "The test message could not be sent.")
    end
    |> noreply()
  end

  defp saved({:ok, channel}, socket, message) do
    socket
    |> close_form()
    |> assign_channels()
    |> flash(:info, message.(channel))
    |> noreply()
  end

  defp saved({:error, %Ecto.Changeset{} = changeset}, socket, _message) do
    socket
    |> assign(:form, form(socket, changeset))
    |> noreply()
  end

  defp saved({:error, :too_many_channels}, socket, _message) do
    socket
    |> close_form()
    |> flash(
      :error,
      "An organization can post to at most #{ChatWebhooks.max_channels_per_org()} #{service_name(socket.assigns.provider)} channels."
    )
    |> noreply()
  end

  defp assign_channels(socket),
    do: assign(socket, :channels, ChatWebhooks.list_channels(socket.assigns.org, socket.assigns.provider))

  defp new_channel(socket), do: %ChatWebhook{provider: socket.assigns.provider, products: []}

  # The form's fields are named for the chat service, so each card's form
  # is told apart: `teams_channel[name]`, `discord_channel[name]`.
  defp form(socket, changeset), do: to_form(changeset, as: "#{socket.assigns.provider}_channel")

  defp channel_params(socket, params), do: Map.get(params, "#{socket.assigns.provider}_channel", %{})

  defp close_form(socket) do
    socket
    |> assign(:editing, nil)
    |> assign(:form, nil)
  end

  defp flash(socket, kind, message) do
    send(self(), {:put_flash, kind, message})
    socket
  end

  defp form_subject(%{assigns: %{editing: :new}} = socket), do: new_channel(socket)
  defp form_subject(%{assigns: %{editing: %ChatWebhook{} = channel}}), do: channel

  # The checkboxes post a blank alongside the checked boxes, so that unticking
  # every box still sends the field and the changeset can say one is needed.
  defp form_params(params) do
    params
    |> Map.update("events", [], &drop_blank/1)
    |> Map.update("products", [], &drop_blank/1)
  end

  defp drop_blank(values), do: Enum.reject(List.wrap(values), &(&1 == ""))

  # Only what was typed into this form. The saved URL is never put back in
  # the page, so editing a channel shows the field empty.
  defp typed_url(form), do: Ecto.Changeset.get_change(form.source, :url) || form.params["url"] || ""

  defp all_products?(form), do: Form.normalize_value("checkbox", form[:all_products].value)

  defp selected_products(form) do
    form.source
    |> Ecto.Changeset.get_field(:products, [])
    |> MapSet.new(& &1.name)
  end

  defp selected_events(form), do: form[:events].value || []

  defp checkbox_errors(form, field) do
    if Phoenix.Component.used_input?(form[field]) do
      Enum.map(form[field].errors, &NervesHubWeb.CoreComponents.translate_error/1)
    else
      []
    end
  end

  defp scope_label(%ChatWebhook{all_products: true}), do: "Every product"
  defp scope_label(%ChatWebhook{products: []}), do: "No products"
  defp scope_label(%ChatWebhook{products: products}), do: Enum.map_join(products, ", ", & &1.name)

  defp error_message(provider, {:rate_limited, seconds}),
    do: "#{service_name(provider)} asked NervesHub to wait #{seconds} seconds"

  defp error_message(_provider, {:refused, reason}), do: reason
  defp error_message(_provider, error), do: to_string(error)

  defp service_name(provider), do: ChatWebhooks.provider(provider).label()

  defp instructions(:teams) do
    ~s(Post this organization's device notifications to Microsoft Teams channels, through a Workflows webhook made in each channel. In Teams, open the channel's menu, choose Workflows, then the "Send webhook alerts to a channel" template, and paste the URL it gives you here.)
  end

  defp instructions(:discord) do
    "Post this organization's device notifications to Discord channels, through a webhook made in each channel. In Discord, open the channel's settings, choose Integrations, then Webhooks, create one, and paste its URL here."
  end

  defp webhook_kind(:teams), do: "Workflows webhook"
  defp webhook_kind(:discord), do: "Webhook"

  defp url_label(:teams, :new), do: "Workflows webhook URL"
  defp url_label(:teams, _editing), do: "New Workflows webhook URL"
  defp url_label(:discord, :new), do: "Webhook URL"
  defp url_label(:discord, _editing), do: "New webhook URL"

  defp toggle_menu(provider, id) do
    JS.toggle(
      to: "##{provider}-channel-#{id}-menu",
      in: {"ease-out duration-150", "opacity-0", "opacity-100"},
      out: {"ease-out duration-150", "opacity-100", "opacity-0"}
    )
  end

  defp hide_menu(js \\ %JS{}, provider, id) do
    JS.hide(js,
      to: "##{provider}-channel-#{id}-menu",
      transition: {"ease-out duration-150", "opacity-100", "opacity-0"}
    )
  end

  attr(:channel, ChatWebhook, required: true)

  defp status_badge(assigns) do
    ~H"""
    <span :if={!@channel.enabled} class="rounded-full border border-base-600 bg-base-800 px-2 py-0.5 text-xs font-medium text-base-400">
      Off
    </span>
    <span
      :if={@channel.enabled && @channel.last_error}
      class="rounded-full border border-alert bg-alert-soft px-2 py-0.5 text-xs font-medium text-alert"
    >
      Failing
    </span>
    <span
      :if={@channel.enabled && is_nil(@channel.last_error)}
      class="rounded-full border border-success px-2 py-0.5 text-xs font-medium text-success"
    >
      On
    </span>
    """
  end
end
