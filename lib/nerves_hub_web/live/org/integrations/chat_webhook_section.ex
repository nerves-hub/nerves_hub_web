defmodule NervesHubWeb.Live.Org.Integrations.ChatWebhookSection do
  @moduledoc """
  A chat service's rows in the Integrations page's chat channels table: the
  Microsoft Teams or Discord channels (`provider`) its device events are
  posted to, each through a webhook made in that channel
  (`NervesHub.Integrations.ChatWebhooks`), and the dialog a channel is added
  and edited in.

  The page loads the channels (`channels`) and passes them in. After a
  change it is told (`:integrations_changed`) and loads them again, since its
  header count, Add integration menu and empty state count them too. It opens
  the dialog for a new channel from that menu, with the `new-channel` event.

  Adding, changing and removing a channel takes the manage role, as webhooks
  and Slack channels do. Everyone in the organization sees each channel's
  name, events, products and state, but nobody sees its webhook's URL once
  it is saved: it is all it takes to post to the channel. Editing a channel
  leaves the URL as it was unless a new one is pasted in.

  Flash messages go to the page (`{:put_flash, kind, message}`): a
  component's own flash is only shown when it navigates.
  """
  use NervesHubWeb, :live_component

  import NervesHubWeb.Live.Org.Integrations.Components

  alias NervesHub.Integrations.ChannelEvents
  alias NervesHub.Integrations.ChatWebhooks
  alias NervesHub.Integrations.ChatWebhooks.ChatWebhook
  alias Phoenix.LiveView.JS

  @impl Phoenix.LiveComponent
  def mount(socket) do
    socket
    |> assign(:event_columns, channel_event_columns())
    |> assign(:testing, MapSet.new())
    |> close_form()
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
        |> changed()
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
    |> changed()
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
    |> changed()
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

  defp new_channel(socket), do: %ChatWebhook{provider: socket.assigns.provider, products: []}

  # The form's fields are named for the chat service, so each service's
  # form is told apart: `teams_channel[name]`, `discord_channel[name]`.
  defp form(socket, changeset), do: to_form(changeset, as: "#{socket.assigns.provider}_channel")

  defp channel_params(socket, params), do: Map.get(params, "#{socket.assigns.provider}_channel", %{})

  defp close_form(socket) do
    socket
    |> assign(:editing, nil)
    |> assign(:form, nil)
  end

  defp changed(socket) do
    send(self(), :integrations_changed)
    socket
  end

  defp flash(socket, kind, message) do
    send(self(), {:put_flash, kind, message})
    socket
  end

  defp form_subject(%{assigns: %{editing: :new}} = socket), do: new_channel(socket)
  defp form_subject(%{assigns: %{editing: %ChatWebhook{} = channel}}), do: channel

  # Only what was typed into this form. The saved URL is never put back in
  # the page, so editing a channel shows the field empty.
  defp typed_url(form), do: Ecto.Changeset.get_change(form.source, :url) || form.params["url"] || ""

  defp status(%ChatWebhook{enabled: false}), do: :off
  defp status(%ChatWebhook{last_error: error}) when is_binary(error), do: :failing
  defp status(%ChatWebhook{}), do: :on

  defp event_labels(channel), do: Enum.map(channel.events, &ChannelEvents.label/1)

  defp error_message(provider, {:rate_limited, seconds}),
    do: "#{service_name(provider)} asked NervesHub to wait #{seconds} seconds"

  defp error_message(_provider, {:refused, reason}), do: reason
  defp error_message(_provider, error), do: to_string(error)

  defp service_name(provider), do: ChatWebhooks.provider(provider).label()

  defp webhook_kind(:teams), do: "Workflows webhook"
  defp webhook_kind(:discord), do: "Channel webhook"

  defp dialog_title(provider, :new), do: "Add a #{service_name(provider)} channel"
  defp dialog_title(_provider, %ChatWebhook{name: name}), do: "Edit #{name}"

  defp url_label(:teams, :new), do: "Workflows webhook URL"
  defp url_label(:teams, _editing), do: "New Workflows webhook URL"
  defp url_label(:discord, :new), do: "Webhook URL"
  defp url_label(:discord, _editing), do: "New webhook URL"

  defp name_placeholder(:teams), do: "Field ops"
  defp name_placeholder(:discord), do: "#hardware-lab"

  defp row_id(provider, channel), do: "#{provider}-channel-#{channel.id}"

  defp dialog_id(provider), do: "#{provider}-dialog"
end
