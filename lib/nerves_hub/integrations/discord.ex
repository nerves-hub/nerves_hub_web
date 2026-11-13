defmodule NervesHub.Integrations.Discord do
  @moduledoc """
  Discord, as a chat service whose channels NervesHub posts to
  (`NervesHub.Integrations.ChatWebhooks`), through a webhook made in the
  channel's settings.

  Messages are embeds (`NervesHub.Integrations.Discord.Embeds`), posted
  under the instance's name, and mention nobody whatever a device sent: each
  says `allowed_mentions: %{parse: []}`.
  """
  @behaviour NervesHub.Integrations.ChatWebhooks.Provider

  alias NervesHub.Integrations.ChatWebhooks.Provider
  alias NervesHub.Integrations.Discord.Embeds
  alias NervesHub.Webhooks.Destination

  # Discord's own hosts. Its webhooks are under the API's path, with or
  # without a version: `/api/webhooks/<id>/<token>`.
  @hosts ["discord.com", "discordapp.com", "canary.discord.com", "ptb.discord.com"]
  @path ~r{\A/api(/v\d+)?/webhooks/\d+/[\w-]+/?\z}

  @impl Provider
  def label(), do: "Discord"

  @doc """
  Whether `url` is a Discord channel webhook NervesHub may post to, with a
  message for the form when it is not.
  """
  @impl Provider
  def check_url(url) do
    case URI.new(url) do
      {:ok, %URI{scheme: "https", host: host, path: path}} when is_binary(host) and host != "" ->
        with :ok <- Destination.validate_url(url) do
          if String.downcase(host) in @hosts and is_binary(path) and Regex.match?(@path, path) do
            :ok
          else
            {:error, "must be the URL Discord gives a channel webhook"}
          end
        end

      {:ok, %URI{}} ->
        {:error, "must start with https://"}

      {:error, _invalid_part} ->
        {:error, "is not a valid URL"}
    end
  end

  @impl Provider
  defdelegate build(key, events), to: Embeds

  @impl Provider
  defdelegate test(org_name, user_name, labels), to: Embeds
end
