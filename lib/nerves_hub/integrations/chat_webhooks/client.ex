defmodule NervesHub.Integrations.ChatWebhooks.Client do
  @moduledoc """
  Posts to a chat service's incoming webhook: a Teams Workflows webhook or a
  Discord channel webhook.

  The request is sent as a webhook delivery is: through
  `NervesHub.Webhooks.Delivery.Adapter`, to an address
  `NervesHub.Webhooks.Destination` checked, without following redirects.

  How the service answers decides what happens next:

    * 2xx: posted (a Teams workflow answers 202, Discord 204).
    * 429: the service's throttling, with how long to wait.
    * 401, 403, 404 and 410: the webhook was deleted or turned off, or its
      URL no longer works. Nothing NervesHub sends will get through until a
      person fixes it, so the channel is turned off
      (`NervesHub.Integrations.ChatWebhooks`).
    * Anything else, or no answer: worth trying again.
  """

  alias NervesHub.Integrations.ChatWebhooks
  alias NervesHub.Webhooks.Delivery.Adapter
  alias NervesHub.Webhooks.Destination

  @user_agent "NervesHub-ChatWebhooks/1.0"

  @refused [401, 403, 404, 410]

  @typedoc "Why a post did not get through."
  @type error() :: {:rate_limited, pos_integer()} | {:refused, String.t()} | String.t()

  @doc """
  Posts `message`, a body the webhook's provider built, to `url`. `label`
  names the chat service in what a refusal says.
  """
  @spec post(String.t(), map(), String.t()) :: :ok | {:error, error()}
  def post(url, message, label) do
    case Destination.resolve(url) do
      {:ok, address} ->
        [
          method: :post,
          url: url,
          headers: [{"content-type", "application/json"}, {"user-agent", @user_agent}],
          body: Jason.encode!(message),
          adapter: Adapter,
          retry: false,
          redirect: false
        ]
        |> Keyword.merge(req_options())
        |> Req.new()
        |> Req.Request.put_private(:webhook_address, address)
        |> Req.request()
        |> result(label)

      {:error, message} ->
        {:error, message}
    end
  end

  defp result({:ok, %Req.Response{status: status}}, _label) when status in 200..299, do: :ok

  defp result({:ok, %Req.Response{status: 429} = response}, _label),
    do: {:error, {:rate_limited, retry_after(response)}}

  defp result({:ok, %Req.Response{status: status}}, label) when status in @refused,
    do: {:error, {:refused, "#{label} refused the webhook (HTTP #{status}): it was deleted or turned off"}}

  defp result({:ok, %Req.Response{status: status}}, _label) when status in 300..399,
    do: {:error, "HTTP #{status}: the webhook redirected, which is not followed"}

  defp result({:ok, %Req.Response{status: status}}, _label), do: {:error, "HTTP #{status}"}
  defp result({:error, exception}, _label), do: {:error, Exception.message(exception)}

  # Whole seconds, rounded up: Discord's can be fractional.
  defp retry_after(response) do
    with [value | _] <- Req.Response.get_header(response, "retry-after"),
         {seconds, _rest} when seconds > 0 <- Float.parse(value) do
      seconds |> Float.ceil() |> trunc()
    else
      _ -> 30
    end
  end

  # Tests stub the webhooks with `plug: {Req.Test, NervesHub.Integrations.ChatWebhooks}`,
  # which takes the place of the adapter.
  defp req_options() do
    :nerves_hub
    |> Application.get_env(ChatWebhooks, [])
    |> Keyword.get(:req_options, [])
  end
end
