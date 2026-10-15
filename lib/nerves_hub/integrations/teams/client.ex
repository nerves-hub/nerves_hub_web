defmodule NervesHub.Integrations.Teams.Client do
  @moduledoc """
  Posts to a Teams channel's Workflows webhook.

  The request is sent as a webhook delivery is: through
  `NervesHub.Webhooks.Delivery.Adapter`, to an address
  `NervesHub.Webhooks.Destination` checked, without following redirects.

  How Power Automate answers decides what happens next:

    * 2xx: posted (a workflow answers 202 once it has the message).
    * 429: Power Automate's throttling, with how long to wait.
    * 401, 403, 404 and 410: the workflow was deleted or turned off, or its
      URL's signature is no longer valid. Nothing NervesHub sends will get
      through until a person fixes the workflow, so the channel is turned
      off (`NervesHub.Integrations.Teams`).
    * Anything else, or no answer: worth trying again.
  """

  alias NervesHub.Integrations.Teams
  alias NervesHub.Webhooks.Delivery.Adapter
  alias NervesHub.Webhooks.Destination

  @user_agent "NervesHub-Teams/1.0"

  @refused [401, 403, 404, 410]

  @typedoc "Why a post did not get through."
  @type error() :: {:rate_limited, pos_integer()} | {:refused, String.t()} | String.t()

  @doc "Posts `message`, a Workflows webhook body (`NervesHub.Integrations.Teams.Cards`), to `url`."
  @spec post(String.t(), map()) :: :ok | {:error, error()}
  def post(url, message) do
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
        |> result()

      {:error, message} ->
        {:error, message}
    end
  end

  defp result({:ok, %Req.Response{status: status}}) when status in 200..299, do: :ok
  defp result({:ok, %Req.Response{status: 429} = response}), do: {:error, {:rate_limited, retry_after(response)}}

  defp result({:ok, %Req.Response{status: status}}) when status in @refused,
    do: {:error, {:refused, "Teams refused the webhook (HTTP #{status}): its workflow was deleted or turned off"}}

  defp result({:ok, %Req.Response{status: status}}) when status in 300..399,
    do: {:error, "HTTP #{status}: the webhook redirected, which is not followed"}

  defp result({:ok, %Req.Response{status: status}}), do: {:error, "HTTP #{status}"}
  defp result({:error, exception}), do: {:error, Exception.message(exception)}

  defp retry_after(response) do
    with [value | _] <- Req.Response.get_header(response, "retry-after"),
         {seconds, ""} when seconds > 0 <- Integer.parse(value) do
      seconds
    else
      _ -> 30
    end
  end

  # Tests stub the webhook with `plug: {Req.Test, NervesHub.Integrations.Teams}`, which
  # takes the place of the adapter.
  defp req_options() do
    :nerves_hub
    |> Application.get_env(Teams, [])
    |> Keyword.get(:req_options, [])
  end
end
