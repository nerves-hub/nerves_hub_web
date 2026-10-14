defmodule NervesHub.Integrations.Slack.Messages do
  @moduledoc """
  The Slack messages NervesHub posts: Block Kit `blocks`, and the plain
  `text` Slack shows in notifications and screen readers.

  A batch of one kind of event becomes one message. A single event gets a
  message of its own; a burst gets a count and the first few devices, so that
  a fleet changing at once is one message rather than hundreds. Each is built
  from the events' data as `NervesHub.Integrations.dispatch/3` raised it (the
  webhook payloads in `NervesHub.Webhooks.Payloads`), read back with string
  keys.

  Whatever a device or a person typed is escaped, so that it cannot mention
  `@channel` or turn into a link.
  """

  @listed 10
  @max_text 300

  @type message() :: %{text: String.t(), blocks: [map()]}

  @status_icons %{
    "unhealthy" => ":red_circle:",
    "warning" => ":large_yellow_circle:",
    "healthy" => ":large_green_circle:",
    "unknown" => ":white_circle:"
  }

  @level_icons %{"error" => ":red_circle:", "warning" => ":warning:", "info" => ":information_source:"}

  @doc "The message for a batch of events of one key (`NervesHub.Integrations.Slack.Events`)."
  @spec build(String.t(), [map(), ...]) :: message()
  def build("device.health_status_changed", events), do: health(events)
  def build("device.firmware_update.failed", events), do: update_failed(events)
  def build("device.firmware_update.succeeded", events), do: update_succeeded(events)
  def build("error_group.created", events), do: errors(events, :created)
  def build("error_group.reopened", events), do: errors(events, :reopened)
  def build("product.notification_created", events), do: notifications(events)

  @doc "What `Send test message` posts."
  @spec test(String.t(), String.t(), [String.t()]) :: message()
  def test(org_name, user_name, labels) do
    text =
      "NervesHub will post #{Enum.join(labels, ", ")} for #{escape(org_name)} here. This test was sent by #{escape(user_name)}."

    %{text: text, blocks: [section(":wave: " <> text)]}
  end

  ## Health

  defp health(events) do
    case last_per_device(events) do
      [event] ->
        status = event["status"]

        text =
          "#{device_label(event)} is now #{status}#{was(event["previous_status"])}"

        %{
          text: text,
          blocks:
            blocks([
              section(
                "#{status_icon(status)} *#{device_link(event)}* is now *#{status}*#{was(event["previous_status"])}"
              ),
              context([product_name(event), reasons(event)])
            ])
        }

      changes ->
        counts =
          changes
          |> Enum.frequencies_by(& &1["status"])
          |> Enum.sort_by(fn {status, _} -> Enum.find_index(~w(unhealthy warning unknown healthy), &(&1 == status)) end)
          |> Enum.map_join(", ", fn {status, count} -> "#{count} #{status}" end)

        summary = "#{length(changes)} devices changed health status: #{counts}"

        lines =
          Enum.map(changes, fn event ->
            "#{status_icon(event["status"])} #{device_link(event)} #{event["status"]}#{was(event["previous_status"])}"
          end)

        %{text: summary, blocks: blocks([section("*#{summary}*") | listed(lines)] ++ [context(product_names(changes))])}
    end
  end

  # A device that changed more than once in the batch is listed once, as it
  # ended up, against where it started.
  defp last_per_device(events) do
    events
    |> Enum.reduce({[], %{}}, fn event, {order, seen} ->
      key = {get_in(event, ["product", "name"]), get_in(event, ["device", "identifier"])}

      case seen do
        %{^key => first} -> {order, Map.put(seen, key, %{event | "previous_status" => first["previous_status"]})}
        _ -> {[key | order], Map.put(seen, key, event)}
      end
    end)
    |> then(fn {order, seen} -> order |> Enum.reverse() |> Enum.map(&Map.fetch!(seen, &1)) end)
  end

  defp was(nil), do: ""
  defp was(previous), do: ", was #{previous}"

  defp status_icon(status), do: Map.get(@status_icons, status, ":white_circle:")

  defp reasons(%{"status" => status, "reasons" => %{} = reasons}) do
    case Map.get(reasons, status) do
      %{} = metrics when map_size(metrics) > 0 ->
        metrics
        |> Enum.map_join(", ", fn {metric, details} -> "#{metric}#{threshold(details)}" end)
        |> truncate()
        |> escape()

      _ ->
        nil
    end
  end

  defp reasons(_event), do: nil

  defp threshold(%{"threshold" => threshold}), do: " (threshold #{threshold})"
  defp threshold(_details), do: ""

  ## Updates

  defp update_failed([event]) do
    text = "Update to #{target(event)} #{failure(event)} on #{device_label(event)}"

    %{
      text: text,
      blocks:
        blocks([
          section(":x: Update to *#{target(event)}* #{failure(event)} on *#{device_link(event)}*#{reason(event)}"),
          context([product_name(event), deployment_group(event), from(event)])
        ])
    }
  end

  defp update_failed(events) do
    summary = "#{length(events)} updates failed"

    lines = Enum.map(events, &"#{device_link(&1)} to #{target(&1)}: #{failure(&1)}#{reason(&1)}")

    %{text: summary, blocks: blocks([section(":x: *#{summary}*") | listed(lines)] ++ [context(product_names(events))])}
  end

  defp update_succeeded([event]) do
    %{
      text: "#{device_label(event)} updated to #{target(event)}",
      blocks:
        blocks([
          section(":white_check_mark: *#{device_link(event)}* updated to *#{target(event)}*"),
          context([product_name(event), deployment_group(event), from(event)])
        ])
    }
  end

  defp update_succeeded(events) do
    versions =
      events
      |> Enum.frequencies_by(&target/1)
      |> Enum.sort_by(fn {_version, count} -> -count end)
      |> Enum.map_join(", ", fn {version, count} -> "#{count} to #{version}" end)

    summary = "#{length(events)} devices updated: #{versions}"
    lines = Enum.map(events, &"#{device_link(&1)} to #{target(&1)}")

    %{
      text: summary,
      blocks: blocks([section(":white_check_mark: *#{summary}*") | listed(lines)] ++ [context(product_names(events))])
    }
  end

  defp target(event) do
    case event["target_firmware"] do
      %{"version" => version} when is_binary(version) -> escape(version)
      %{"uuid" => uuid} when is_binary(uuid) -> escape(uuid)
      _ -> "new firmware"
    end
  end

  defp from(event) do
    case event["source_firmware"] do
      %{"version" => version} when is_binary(version) -> "from #{escape(version)}"
      _ -> nil
    end
  end

  defp failure(%{"outcome" => "expired"}), do: "stopped reporting progress"
  defp failure(%{"outcome" => "abandoned"}), do: "ended back on the old firmware"
  defp failure(_event), do: "failed"

  defp reason(%{"reason" => reason}) when is_binary(reason) and reason != "", do: ": #{escape(truncate(reason))}"
  defp reason(_event), do: ""

  defp deployment_group(%{"deployment_group" => %{"name" => name}}), do: "deployment group #{escape(name)}"
  defp deployment_group(_event), do: nil

  ## Errors

  defp errors([event], kind) do
    {icon, heading} =
      case kind do
        :created -> {":rotating_light:", "New error in"}
        :reopened -> {":leftwards_arrow_with_hook:", "Error reopened in"}
      end

    product = product_name(event) || "a product"

    %{
      text: "#{heading} #{product}: #{escape(truncate(get_in(event, ["error", "reason"]) || ""))}",
      blocks:
        blocks([
          section("#{icon} #{heading} *#{product}*: #{code(get_in(event, ["error", "reason"]))}"),
          context([top_frame(event), "<#{error_url(event)}|View the error>"])
        ])
    }
  end

  defp errors(events, kind) do
    {icon, summary} =
      case kind do
        :created -> {":rotating_light:", "#{length(events)} new errors"}
        :reopened -> {":leftwards_arrow_with_hook:", "#{length(events)} errors reopened"}
      end

    lines =
      Enum.map(events, &"<#{error_url(&1)}|#{escape(String.slice(get_in(&1, ["error", "reason"]) || "", 0, 80))}>")

    %{
      text: summary,
      blocks: blocks([section("#{icon} *#{summary}*") | listed(lines)] ++ [context(product_names(events))])
    }
  end

  defp top_frame(event) do
    case get_in(event, ["error", "top_frame"]) do
      nil -> nil
      frame -> escape(truncate(frame))
    end
  end

  # An inline code span, which a backtick in the text would end early.
  defp code(nil), do: "an error"
  defp code(text), do: "`#{text |> truncate() |> String.replace("`", "'") |> escape()}`"

  defp error_url(event) do
    "#{base_url()}/org/#{segment(get_in(event, ["org", "name"]) || "")}/#{segment(get_in(event, ["product", "name"]) || "")}/errors/#{get_in(event, ["error", "id"])}"
  end

  ## Product notifications

  @notifications_listed 5

  defp notifications(events) do
    shown = Enum.take(events, @notifications_listed)
    more = length(events) - length(shown)

    blocks =
      Enum.flat_map(shown, fn event ->
        notification = event["notification"] || %{}
        icon = Map.get(@level_icons, notification["level"], ":information_source:")

        [
          section(
            "#{icon} *#{escape(notification["title"] || "")}*\n#{escape(truncate(notification["message"] || ""))}"
          ),
          context([product_name(event), "<#{notifications_url(event)}|Notifications>"])
        ]
      end)

    blocks =
      if more > 0 do
        blocks ++ [context(["And #{more} more on the products' Notifications pages."])]
      else
        blocks
      end

    text =
      case shown do
        [event] -> get_in(event, ["notification", "title"]) || "A product notification"
        _ -> "#{length(events)} product notifications"
      end

    %{text: text, blocks: blocks(blocks)}
  end

  ## Shared

  defp listed(lines) do
    {shown, rest} = Enum.split(lines, @listed)

    lines =
      if rest == [] do
        shown
      else
        shown ++ ["and #{length(rest)} more"]
      end

    [section(Enum.map_join(lines, "\n", &("• " <> &1)))]
  end

  defp section(text), do: %{type: "section", text: %{type: "mrkdwn", text: text}}

  # Slack refuses a context block with no elements, or an element with no
  # text, so one with nothing to say is left out (`blocks/1`).
  defp context(elements) do
    case Enum.reject(elements, &(&1 in [nil, ""])) do
      [] -> nil
      elements -> %{type: "context", elements: Enum.map(elements, &%{type: "mrkdwn", text: &1})}
    end
  end

  defp blocks(blocks), do: Enum.reject(blocks, &is_nil/1)

  defp product_name(event) do
    case get_in(event, ["product", "name"]) do
      nil -> nil
      name -> escape(name)
    end
  end

  defp product_names(events) do
    [events |> Enum.map(&product_name/1) |> Enum.reject(&is_nil/1) |> Enum.uniq() |> Enum.join(", ")]
  end

  defp device_label(event) do
    case get_in(event, ["device", "identifier"]) do
      nil -> "a device"
      identifier -> escape(identifier)
    end
  end

  defp device_link(event) do
    with org when is_binary(org) <- get_in(event, ["org", "name"]),
         product when is_binary(product) <- get_in(event, ["product", "name"]),
         identifier when is_binary(identifier) <- get_in(event, ["device", "identifier"]) do
      "<#{base_url()}/org/#{segment(org)}/#{segment(product)}/devices/#{segment(identifier)}|#{escape(identifier)}>"
    else
      _ -> device_label(event)
    end
  end

  defp notifications_url(event) do
    "#{base_url()}/org/#{segment(get_in(event, ["org", "name"]) || "")}/#{segment(get_in(event, ["product", "name"]) || "")}/notifications"
  end

  defp base_url(), do: NervesHubWeb.Endpoint.url()

  defp segment(value), do: URI.encode(value, &URI.char_unreserved?/1)

  # Slack's control characters in mrkdwn. Escaping them is what keeps text a
  # device sent from becoming `<!channel>` or a link.
  defp escape(value) do
    value
    |> to_string()
    |> String.replace(["&", "<", ">"], fn
      "&" -> "&amp;"
      "<" -> "&lt;"
      ">" -> "&gt;"
    end)
  end

  defp truncate(text) do
    text = to_string(text)
    if String.length(text) > @max_text, do: String.slice(text, 0, @max_text) <> "…", else: text
  end
end
