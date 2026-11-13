defmodule NervesHub.Webhooks.Delivery do
  @moduledoc """
  Sends one delivery attempt to a webhook's endpoint, and reports how it went.

  A delivery is a signed `POST` of the event's JSON (see
  `NervesHub.Webhooks.Signature`). Any 2xx response is success. Redirects are
  not followed, because the address a redirect points at has not been checked
  (`NervesHub.Webhooks.Destination`), so a 3xx counts as a failure and the
  message says why.

  Requests go through `NervesHub.Webhooks.Delivery.Adapter`, which opens one
  connection per delivery to the address `Destination.resolve/2` checked.
  """

  alias NervesHub.Webhooks.Delivery.Adapter
  alias NervesHub.Webhooks.Destination
  alias NervesHub.Webhooks.Signature
  alias NervesHub.Webhooks.Webhook

  @typedoc """
  How an attempt went: the response status for a 2xx, otherwise the status
  (when there was a response) and a message for the person reading the
  webhook's settings.
  """
  @type result() :: {:ok, pos_integer()} | {:error, pos_integer() | nil, String.t()}

  @user_agent "NervesHub-Webhooks/1.0"

  @doc """
  Send `body`, the encoded event, to `webhook`, signed as event `event_id`.
  """
  @spec deliver(Webhook.t(), String.t(), binary()) :: result()
  def deliver(%Webhook{} = webhook, event_id, body) do
    timestamp = System.os_time(:second)

    headers = [
      {"content-type", "application/json"},
      {"user-agent", @user_agent},
      {"webhook-id", event_id},
      {"webhook-timestamp", Integer.to_string(timestamp)},
      {"webhook-signature", Signature.sign(webhook.secret, event_id, timestamp, body)}
    ]

    case Destination.resolve(webhook.url) do
      {:ok, address} ->
        [method: :post, url: webhook.url, headers: headers, body: body, adapter: Adapter, retry: false, redirect: false]
        |> Keyword.merge(req_options())
        |> Req.new()
        |> Req.Request.put_private(:webhook_address, address)
        |> Req.request()
        |> result()

      {:error, message} ->
        {:error, nil, message}
    end
  end

  defp result({:ok, %Req.Response{status: status}}) when status in 200..299, do: {:ok, status}

  defp result({:ok, %Req.Response{status: status} = response}) when status in 300..399 do
    location = response |> Req.Response.get_header("location") |> List.first()

    {:error, status, "HTTP #{status}: redirected to #{location || "another address"}, which is not followed"}
  end

  defp result({:ok, %Req.Response{status: status}}), do: {:error, status, "HTTP #{status}"}

  defp result({:error, exception}), do: {:error, nil, Exception.message(exception)}

  # Tests stub the endpoint with `plug: {Req.Test, ...}`, which takes the place
  # of the adapter.
  defp req_options() do
    :nerves_hub
    |> Application.get_env(NervesHub.Webhooks, [])
    |> Keyword.get(:req_options, [])
  end
end
