defmodule NervesHubWeb.Live.Org.Integrations.SlackSection do
  @moduledoc """
  Slack's rows in the Integrations page's chat channels table: the channels
  of the organization's Slack workspaces that its device events are posted
  to, and the dialog a channel is added and edited in.

  The page loads the workspaces' connections, with their channels
  (`connections`), and passes them in. It draws each workspace's line at the
  foot of the table, whose Disconnect button sends `disconnect` here, and
  opens the dialog for a new channel from its Add integration menu, with
  `new-channel` and the connection. After a change it is told
  (`:integrations_changed`) and loads them again.

  Connecting and disconnecting a workspace takes an admin; choosing channels
  and events takes the manage role, as webhooks do. Everyone in the
  organization sees what is connected and where events go.

  The channel picker lists what Slack says the app can post to, read when the
  dialog opens. A channel is saved only if it was in that list, so the form
  cannot be used to aim the app at a channel id typed in by hand.

  Flash messages go to the page (`{:put_flash, kind, message}`): a
  component's own flash is only shown when it navigates.
  """
  use NervesHubWeb, :live_component

  import NervesHubWeb.Live.Org.Integrations.Components

  alias NervesHub.Branding
  alias NervesHub.Integrations.ChannelEvents
  alias NervesHub.Integrations.Slack
  alias NervesHub.Integrations.Slack.Subscription
  alias NervesHub.Integrations.Slack.Subscriptions
  alias Phoenix.LiveView.AsyncResult
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
  def handle_event("disconnect", %{"connection_id" => id}, socket) do
    authorized!(:"slack_connection:delete", socket.assigns.current_scope)

    connection = Slack.get_connection!(socket.assigns.org, id)
    :ok = Slack.disconnect(socket.assigns.current_scope, connection)

    socket
    |> close_form()
    |> changed()
    |> flash(:info, "Disconnected the #{connection.workspace.team_name} Slack workspace.")
    |> noreply()
  end

  def handle_event("new-channel", %{"connection_id" => id}, socket) do
    authorized!(:"slack_subscription:create", socket.assigns.current_scope)

    connection = Slack.get_connection!(socket.assigns.org, id)
    changeset = Subscriptions.change_subscription(socket.assigns.org, %Subscription{products: []})

    socket
    |> assign(:editing, {:new, connection})
    |> assign(:selected_channel, nil)
    |> assign(:form, to_form(changeset, as: :slack_subscription))
    |> assign(:channels, AsyncResult.loading())
    |> start_async(:channels, fn -> Subscriptions.list_channels(connection) end)
    |> noreply()
  end

  def handle_event("edit-channel", %{"subscription_id" => id}, socket) do
    authorized!(:"slack_subscription:update", socket.assigns.current_scope)

    subscription = Subscriptions.get_subscription!(socket.assigns.org, id)
    changeset = Subscriptions.change_subscription(socket.assigns.org, subscription)

    socket
    |> assign(:editing, subscription)
    |> assign(:form, to_form(changeset, as: :slack_subscription))
    |> noreply()
  end

  def handle_event("cancel", _params, socket) do
    socket
    |> close_form()
    |> noreply()
  end

  def handle_event("validate", %{"slack_subscription" => params}, socket) do
    params = form_params(params)

    changeset =
      socket.assigns.org
      |> Subscriptions.change_subscription(form_subject(socket.assigns.editing), params)
      |> Map.put(:action, :validate)

    socket
    |> assign(:form, to_form(changeset, as: :slack_subscription))
    |> assign(:selected_channel, params["channel_id"])
    |> noreply()
  end

  def handle_event("save", %{"slack_subscription" => params}, socket) do
    params = form_params(params)

    case socket.assigns.editing do
      {:new, connection} -> create(socket, connection, params)
      %Subscription{} = subscription -> update_subscription(socket, subscription, params)
    end
  end

  def handle_event("toggle", %{"subscription_id" => id}, socket) do
    authorized!(:"slack_subscription:update", socket.assigns.current_scope)

    subscription = Subscriptions.get_subscription!(socket.assigns.org, id)

    case Subscriptions.update_subscription(socket.assigns.current_scope, subscription, %{
           enabled: !subscription.enabled
         }) do
      {:ok, updated} ->
        socket
        |> changed()
        |> flash(:info, "Posting to ##{updated.channel_name} is #{if updated.enabled, do: "on", else: "off"}.")
        |> noreply()

      {:error, _changeset} ->
        socket
        |> flash(:error, "The channel could not be changed. Edit it to see what needs fixing.")
        |> noreply()
    end
  end

  def handle_event("delete", %{"subscription_id" => id}, socket) do
    authorized!(:"slack_subscription:delete", socket.assigns.current_scope)

    subscription = Subscriptions.get_subscription!(socket.assigns.org, id)
    {:ok, _} = Subscriptions.delete_subscription(socket.assigns.current_scope, subscription)

    socket
    |> close_form()
    |> changed()
    |> flash(:info, "NervesHub stopped posting to ##{subscription.channel_name}.")
    |> noreply()
  end

  # Off the LiveView process: Slack not answering would otherwise freeze the
  # page for the whole timeout.
  def handle_event("send-test", %{"subscription_id" => id}, socket) do
    authorized!(:"slack_subscription:update", socket.assigns.current_scope)

    subscription = Subscriptions.get_subscription!(socket.assigns.org, id)
    scope = socket.assigns.current_scope

    socket
    |> update(:testing, &MapSet.put(&1, subscription.id))
    |> start_async({:send_test, subscription.id}, fn ->
      {subscription.channel_name, Subscriptions.send_test_message(scope, subscription)}
    end)
    |> noreply()
  end

  @impl Phoenix.LiveComponent
  def handle_async(:channels, {:ok, {:ok, channels}}, socket) do
    assign(socket, :channels, AsyncResult.ok(socket.assigns.channels, channels)) |> noreply()
  end

  def handle_async(:channels, {:ok, {:error, error}}, socket) do
    assign(socket, :channels, AsyncResult.failed(socket.assigns.channels, error)) |> noreply()
  end

  def handle_async(:channels, {:exit, reason}, socket) do
    assign(socket, :channels, AsyncResult.failed(socket.assigns.channels, reason)) |> noreply()
  end

  def handle_async({:send_test, id}, result, socket) do
    socket = update(socket, :testing, &MapSet.delete(&1, id))

    case result do
      {:ok, {channel, :ok}} ->
        flash(socket, :info, "Posted a test message to ##{channel}.")

      {:ok, {channel, {:error, error}}} ->
        flash(socket, :error, "Slack refused the test message to ##{channel}: #{error_message(error)}")

      {:exit, _reason} ->
        flash(socket, :error, "The test message could not be sent.")
    end
    |> noreply()
  end

  defp create(socket, connection, params) do
    authorized!(:"slack_subscription:create", socket.assigns.current_scope)

    case listed_channel(socket, params["channel_id"]) do
      nil ->
        socket
        |> flash(:error, "Choose a channel from the list.")
        |> noreply()

      channel ->
        params = Map.merge(params, %{"channel_id" => channel.id, "channel_name" => channel.name})

        socket.assigns.current_scope
        |> Subscriptions.create_subscription(connection, params)
        |> saved(socket, "NervesHub will post to ##{channel.name}.")
    end
  end

  defp update_subscription(socket, subscription, params) do
    authorized!(:"slack_subscription:update", socket.assigns.current_scope)

    socket.assigns.current_scope
    |> Subscriptions.update_subscription(subscription, params)
    |> saved(socket, "The channel was updated.")
  end

  defp saved({:ok, _subscription}, socket, message) do
    socket
    |> close_form()
    |> changed()
    |> flash(:info, message)
    |> noreply()
  end

  defp saved({:error, %Ecto.Changeset{} = changeset}, socket, _message) do
    socket
    |> assign(:form, to_form(changeset, as: :slack_subscription))
    |> noreply()
  end

  defp saved({:error, :too_many_subscriptions}, socket, _message) do
    socket
    |> close_form()
    |> flash(
      :error,
      "An organization can post to at most #{Subscriptions.max_subscriptions_per_org()} Slack channels."
    )
    |> noreply()
  end

  # Only a channel Slack listed when the form opened.
  defp listed_channel(%{assigns: %{channels: %AsyncResult{ok?: true, result: channels}}}, id) when is_binary(id) do
    Enum.find(channels, &(&1.id == id))
  end

  defp listed_channel(_socket, _id), do: nil

  defp close_form(socket) do
    socket
    |> assign(:editing, nil)
    |> assign(:form, nil)
    |> assign(:selected_channel, nil)
    |> assign(:channels, nil)
  end

  defp changed(socket) do
    send(self(), :integrations_changed)
    socket
  end

  defp flash(socket, kind, message) do
    send(self(), {:put_flash, kind, message})
    socket
  end

  defp form_subject({:new, _connection}), do: %Subscription{products: []}
  defp form_subject(%Subscription{} = subscription), do: subscription

  defp channel_options(channels) do
    Enum.map(channels, fn
      %{private: true} = channel -> {"#{channel.name} (private)", channel.id}
      channel -> {"##{channel.name}", channel.id}
    end)
  end

  defp status(%Subscription{enabled: false}), do: :off
  defp status(%Subscription{last_error: error}) when is_binary(error), do: :failing
  defp status(%Subscription{}), do: :on

  defp event_labels(subscription), do: Enum.map(subscription.events, &ChannelEvents.label/1)

  defp dialog_title({:new, _connection}), do: "Add a Slack channel"
  defp dialog_title(%Subscription{channel_name: name}), do: "Edit ##{name}"

  defp error_message({:rate_limited, seconds}), do: "Slack asked NervesHub to wait #{seconds} seconds"
  defp error_message(error), do: to_string(error)

  defp row_id(subscription), do: "slack-subscription-#{subscription.id}"
end
