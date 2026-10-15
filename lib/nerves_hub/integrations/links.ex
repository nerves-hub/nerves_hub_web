defmodule NervesHub.Integrations.Links do
  @moduledoc """
  Links to NervesHub's pages from the messages chat channels are sent
  (`NervesHub.Integrations.Slack.Messages`, `NervesHub.Integrations.Teams.Cards`), built from an
  event's data as `NervesHub.Integrations.dispatch/3` raised it, read back
  with string keys.

  The functions taking an event return `nil` when it lacks a name the page
  needs.
  """

  @doc "A device's page."
  @spec device(String.t(), String.t(), String.t()) :: String.t()
  def device(org_name, product_name, identifier) do
    url("/org/#{segment(org_name)}/#{segment(product_name)}/devices/#{segment(identifier)}")
  end

  @doc "The page of the device an event is about."
  @spec device(map()) :: String.t() | nil
  def device(event) do
    with {org, product} <- names(event),
         identifier when is_binary(identifier) <- get_in(event, ["device", "identifier"]) do
      device(org, product, identifier)
    else
      _ -> nil
    end
  end

  @doc "The page of the deployment group an event is about."
  @spec deployment_group(map()) :: String.t() | nil
  def deployment_group(event) do
    with {org, product} <- names(event),
         name when is_binary(name) <- get_in(event, ["deployment_group", "name"]) do
      url("/org/#{segment(org)}/#{segment(product)}/deployment_groups/#{segment(name)}")
    else
      _ -> nil
    end
  end

  @doc "The page of the error an event is about."
  @spec error(map()) :: String.t() | nil
  def error(event) do
    with {org, product} <- names(event),
         id when is_integer(id) <- get_in(event, ["error", "id"]) do
      url("/org/#{segment(org)}/#{segment(product)}/errors/#{id}")
    else
      _ -> nil
    end
  end

  @doc "The Notifications page of the product an event is about."
  @spec notifications(map()) :: String.t() | nil
  def notifications(event) do
    with {org, product} <- names(event) do
      url("/org/#{segment(org)}/#{segment(product)}/notifications")
    end
  end

  defp names(event) do
    with org when is_binary(org) <- get_in(event, ["org", "name"]),
         product when is_binary(product) <- get_in(event, ["product", "name"]) do
      {org, product}
    else
      _ -> nil
    end
  end

  defp url(path), do: NervesHubWeb.Endpoint.url() <> path

  defp segment(value), do: URI.encode(value, &URI.char_unreserved?/1)
end
