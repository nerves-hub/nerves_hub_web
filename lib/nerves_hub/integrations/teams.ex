defmodule NervesHub.Integrations.Teams do
  @moduledoc """
  Microsoft Teams, as a chat service whose channels NervesHub posts to
  (`NervesHub.Integrations.ChatWebhooks`), through a Workflows webhook made
  in the channel.

  Teams retired its incoming webhooks (Office 365 connectors) in May 2026.
  A Workflows webhook is their replacement: a Power Automate flow, made from
  the channel, that posts the Adaptive Cards it is sent
  (`NervesHub.Integrations.Teams.Cards`). Nothing comes back from it: a card
  cannot have buttons that act, and a card once posted cannot be changed.
  """
  @behaviour NervesHub.Integrations.ChatWebhooks.Provider

  alias NervesHub.Integrations.ChatWebhooks.Provider
  alias NervesHub.Integrations.Teams.Cards
  alias NervesHub.Webhooks.Destination

  # Where Teams' Workflows webhooks live: Power Automate's trigger URLs, on
  # its older host and its newer one. Anything else is somebody else's
  # endpoint, which a webhook is for.
  @default_hosts [".logic.azure.com", ".api.powerplatform.com"]

  # Office 365 connector URLs, which Microsoft retired in May 2026.
  @connector_hosts ["webhook.office.com", "outlook.office.com"]

  @impl Provider
  def label(), do: "Microsoft Teams"

  @doc """
  Whether `url` is a Teams Workflows webhook NervesHub may post to, with a
  message for the form when it is not.

  The hosts accepted are Power Automate's (`config :nerves_hub,
  NervesHub.Integrations.Teams, hosts:` overrides them, for a sovereign
  cloud such as GCC High), and the address must be one a webhook could be
  sent to (`NervesHub.Webhooks.Destination`).
  """
  @impl Provider
  def check_url(url) do
    case URI.new(url) do
      {:ok, %URI{scheme: "https", host: host}} when is_binary(host) and host != "" ->
        with :ok <- Destination.validate_url(url), do: check_host(String.downcase(host))

      {:ok, %URI{}} ->
        {:error, "must start with https://"}

      {:error, _invalid_part} ->
        {:error, "is not a valid URL"}
    end
  end

  defp check_host(host) do
    cond do
      Enum.any?(@connector_hosts, &String.ends_with?(host, &1)) ->
        {:error,
         "is an Office 365 connector URL, which Microsoft retired in 2026. Add a Workflows webhook to the channel instead."}

      Enum.any?(hosts(), &String.ends_with?(host, &1)) ->
        :ok

      true ->
        {:error, "must be the URL Teams gives a Workflows webhook"}
    end
  end

  defp hosts() do
    :nerves_hub
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:hosts, @default_hosts)
  end

  @impl Provider
  defdelegate build(key, events), to: Cards

  @impl Provider
  defdelegate test(org_name, user_name, labels), to: Cards
end
