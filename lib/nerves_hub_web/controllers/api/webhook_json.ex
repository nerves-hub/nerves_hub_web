defmodule NervesHubWeb.API.WebhookJSON do
  @moduledoc """
  Renders an organization's webhooks.

  Webhooks are built field by field so the signing secret cannot slip in.
  `with_secret/1` is the one view that includes it, and only the actions that
  make a secret (create, regenerate) render it.
  """

  def index(%{webhooks: webhooks}) do
    %{data: for(webhook <- webhooks, do: webhook(webhook))}
  end

  def show(%{webhook: webhook}) do
    %{data: webhook(webhook)}
  end

  def with_secret(%{webhook: webhook}) do
    %{data: webhook |> webhook() |> Map.put(:secret, webhook.secret)}
  end

  def test_result(%{result: {:ok, status}}) do
    %{data: %{delivered: true, status: status, error: nil}}
  end

  def test_result(%{result: {:error, status, message}}) do
    %{data: %{delivered: false, status: status, error: message}}
  end

  defp webhook(webhook) do
    %{
      id: webhook.id,
      url: webhook.url,
      description: webhook.description,
      events: webhook.events,
      all_products: webhook.all_products,
      products: Enum.map(webhook.products, & &1.name),
      enabled: webhook.enabled,
      disabled_reason: webhook.disabled_reason,
      failing_since: webhook.failing_since,
      last_error: webhook.last_error,
      last_error_at: webhook.last_error_at,
      inserted_at: webhook.inserted_at,
      updated_at: webhook.updated_at
    }
  end
end
