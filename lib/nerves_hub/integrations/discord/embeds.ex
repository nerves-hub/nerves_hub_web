defmodule NervesHub.Integrations.Discord.Embeds do
  @moduledoc """
  The Discord messages NervesHub posts to a channel's webhook: embeds, built
  from the same event data as Slack's messages and Teams' cards.

  A batch of one kind of event becomes one message. A single event gets an
  embed of its own, titled with what happened and linked to its page in
  NervesHub; a burst gets a count and the first few devices. A message about
  workflow steps or product notifications has an embed for each of the first
  few.

  Whatever a device or a person typed is escaped, so Discord's markdown in it
  is shown rather than followed, and every message says
  `allowed_mentions: %{parse: []}`, so nothing in it can ping anybody.
  """

  alias NervesHub.Branding
  alias NervesHub.Integrations.Links

  @listed 10
  @shown 5
  @max_text 300

  # Discord's limits on an embed's parts.
  @max_title 256
  @max_description 4096

  @red 0xE01E5A
  @yellow 0xECB22E
  @green 0x2EB67D
  @grey 0x95A5A6
  @blue 0x5865F2

  @status_icons %{"unhealthy" => "🔴", "warning" => "🟡", "healthy" => "🟢", "unknown" => "⚪"}
  @status_colors %{"unhealthy" => @red, "warning" => @yellow, "healthy" => @green}
  @level_icons %{"error" => "🔴", "warning" => "⚠️", "info" => "ℹ️"}
  @level_colors %{"error" => @red, "warning" => @yellow, "info" => @blue}

  @type message() :: %{required(atom()) => term()}

  @doc "The message for a batch of events of one key (`NervesHub.Integrations.ChannelEvents`)."
  @spec build(String.t(), [map(), ...]) :: message()
  def build("device.health_status_changed", events), do: health(events)
  def build("device.firmware_update.failed", events), do: update_failed(events)
  def build("device.firmware_update.succeeded", events), do: update_succeeded(events)
  def build("error_group.created", events), do: errors(events, :created)
  def build("error_group.reopened", events), do: errors(events, :reopened)
  def build("deployment_group.workflow_step." <> event, events), do: workflow(events, event)
  def build("product.notification_created", events), do: notifications(events)

  @doc "What `Send test message` posts."
  @spec test(String.t(), String.t(), [String.t()]) :: message()
  def test(org_name, user_name, labels) do
    message([
      %{
        description:
          "👋 #{escape(Branding.friendly_platform_name())} will post #{escape(Enum.join(labels, ", "))} for #{escape(org_name)} here. This test was sent by #{escape(user_name)}.",
        color: @blue
      }
    ])
  end

  ## Health

  defp health([event]) do
    status = event["status"]

    message([
      %{
        title: "#{status_icon(status)} #{device_name(event)} is now #{status}",
        url: Links.device(event),
        description: Enum.join(Enum.reject([was(event["previous_status"]), reasons(event)], &is_nil/1), "\n"),
        color: Map.get(@status_colors, status, @grey),
        footer: footer([product_name(event)])
      }
    ])
  end

  defp health(events) do
    changes = last_per_device(events)

    counts =
      changes
      |> Enum.frequencies_by(& &1["status"])
      |> Enum.sort_by(fn {status, _} -> Enum.find_index(~w(unhealthy warning unknown healthy), &(&1 == status)) end)
      |> Enum.map_join(", ", fn {status, count} -> "#{count} #{status}" end)

    lines =
      Enum.map(changes, fn event ->
        "#{status_icon(event["status"])} #{device_link(event)} #{escape(event["status"])}#{previous(event["previous_status"])}"
      end)

    message([
      %{
        title: "#{length(changes)} devices changed health status: #{counts}",
        description: listed(lines),
        color: if(Enum.any?(changes, &(&1["status"] == "unhealthy")), do: @red, else: @yellow),
        footer: footer(product_names(changes))
      }
    ])
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

  defp was(nil), do: nil
  defp was(previous), do: "Was #{escape(previous)}."

  defp previous(nil), do: ""
  defp previous(previous), do: ", was #{escape(previous)}"

  defp status_icon(status), do: Map.get(@status_icons, status, "⚪")

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
    message([
      %{
        title: "❌ Update to #{target(event)} #{failure(event)} on #{device_name(event)}",
        url: Links.device(event),
        description: reason(event),
        color: @red,
        footer: footer([product_name(event), deployment_group(event), from(event)])
      }
    ])
  end

  defp update_failed(events) do
    lines = Enum.map(events, &"#{device_link(&1)} to #{escape(target(&1))}: #{failure(&1)}#{reason_suffix(&1)}")

    message([
      %{
        title: "❌ #{length(events)} updates failed",
        description: listed(lines),
        color: @red,
        footer: footer(product_names(events))
      }
    ])
  end

  defp update_succeeded([event]) do
    message([
      %{
        title: "✅ #{device_name(event)} updated to #{target(event)}",
        url: Links.device(event),
        color: @green,
        footer: footer([product_name(event), deployment_group(event), from(event)])
      }
    ])
  end

  defp update_succeeded(events) do
    versions =
      events
      |> Enum.frequencies_by(&target/1)
      |> Enum.sort_by(fn {_version, count} -> -count end)
      |> Enum.map_join(", ", fn {version, count} -> "#{count} to #{version}" end)

    lines = Enum.map(events, &"#{device_link(&1)} to #{escape(target(&1))}")

    message([
      %{
        title: "✅ #{length(events)} devices updated: #{versions}",
        description: listed(lines),
        color: @green,
        footer: footer(product_names(events))
      }
    ])
  end

  defp target(event) do
    case event["target_firmware"] do
      %{"version" => version} when is_binary(version) -> version
      %{"uuid" => uuid} when is_binary(uuid) -> uuid
      _ -> "new firmware"
    end
  end

  defp from(event) do
    case event["source_firmware"] do
      %{"version" => version} when is_binary(version) -> "from #{version}"
      _ -> nil
    end
  end

  defp failure(%{"outcome" => "expired"}), do: "stopped reporting progress"
  defp failure(%{"outcome" => "abandoned"}), do: "ended back on the old firmware"
  defp failure(_event), do: "failed"

  defp reason(%{"reason" => reason}) when is_binary(reason) and reason != "", do: escape(truncate(reason))
  defp reason(_event), do: nil

  defp reason_suffix(event) do
    case reason(event) do
      nil -> ""
      reason -> ": #{reason}"
    end
  end

  defp deployment_group(%{"deployment_group" => %{"name" => name}}), do: "deployment group #{name}"
  defp deployment_group(_event), do: nil

  ## Errors

  defp errors([event], kind) do
    {icon, heading} =
      case kind do
        :created -> {"🚨", "New error in"}
        :reopened -> {"↩️", "Error reopened in"}
      end

    message([
      %{
        title: "#{icon} #{heading} #{product_name(event) || "a product"}",
        url: Links.error(event),
        description: escape(truncate(get_in(event, ["error", "reason"]) || "An error")),
        color: @red,
        footer: footer([get_in(event, ["error", "top_frame"])])
      }
    ])
  end

  defp errors(events, kind) do
    title =
      case kind do
        :created -> "🚨 #{length(events)} new errors"
        :reopened -> "↩️ #{length(events)} errors reopened"
      end

    lines = Enum.map(events, &link(String.slice(get_in(&1, ["error", "reason"]) || "", 0, 80), Links.error(&1)))

    message([%{title: title, description: listed(lines), color: @red, footer: footer(product_names(events))}])
  end

  ## Deployment workflows

  # One embed each rather than a count: a few deployment groups moving at
  # once is still few enough to read.
  defp workflow(events, event) do
    shown = Enum.take(events, @shown)
    more = length(events) - length(shown)

    embeds =
      Enum.map(shown, fn data ->
        %{
          title: step_sentence(event, data),
          url: Links.deployment_group(data),
          color: step_color(event),
          footer: footer([product_name(data), release(data)])
        }
      end)

    message(embeds ++ more_embed(more, "the deployment groups' pages"))
  end

  defp step_sentence(event, data) do
    step = "#{step_name(data)}#{step_position(data)}"
    group = group_name(data)

    case {event, get_in(data, ["user", "name"])} do
      {"started", nil} -> "▶️ #{step} started for #{group}"
      {"started", by} -> "🔁 #{by} retried #{step} for #{group}"
      {"awaiting_approval", _} -> "✋ #{group} is waiting for approval at #{step}"
      {"completed", nil} -> "✅ #{step} completed for #{group}"
      {"completed", by} -> "✅ #{by} approved #{step} for #{group}"
      {"skipped", nil} -> "⏩ #{step} was skipped for #{group}"
      {"skipped", by} -> "⏩ #{by} skipped #{step} for #{group}"
      {"failed", _} -> "❌ #{step} failed for #{group}#{failed_devices(data)}"
    end
  end

  defp step_name(data), do: get_in(data, ["step", "name"]) || "a step"
  defp group_name(data), do: get_in(data, ["deployment_group", "name"]) || "a deployment group"

  defp step_color("failed"), do: @red
  defp step_color("awaiting_approval"), do: @yellow
  defp step_color("completed"), do: @green
  defp step_color("skipped"), do: @grey
  defp step_color(_event), do: @blue

  defp step_position(data) do
    case {get_in(data, ["step", "number"]), get_in(data, ["workflow", "steps"])} do
      {number, steps} when is_integer(number) and is_integer(steps) -> " (step #{number} of #{steps})"
      _ -> ""
    end
  end

  defp failed_devices(%{"failed_devices" => 1}), do: ": 1 device could not take the update"

  defp failed_devices(%{"failed_devices" => count}) when is_integer(count),
    do: ": #{count} devices could not take the update"

  defp failed_devices(_data), do: ""

  defp release(data) do
    number = get_in(data, ["release", "number"])

    case get_in(data, ["release", "firmware", "version"]) do
      version when is_binary(version) -> "release #{number}, firmware #{version}"
      _ -> number && "release #{number}"
    end
  end

  ## Product notifications

  defp notifications(events) do
    shown = Enum.take(events, @shown)
    more = length(events) - length(shown)

    embeds =
      Enum.map(shown, fn event ->
        notification = event["notification"] || %{}

        %{
          title: "#{Map.get(@level_icons, notification["level"], "ℹ️")} #{notification["title"] || ""}",
          url: Links.notifications(event),
          description: escape(truncate(notification["message"] || "")),
          color: Map.get(@level_colors, notification["level"], @blue),
          footer: footer([product_name(event)])
        }
      end)

    message(embeds ++ more_embed(more, "the products' Notifications pages"))
  end

  ## Building blocks

  # A title cannot hold a link, and `allowed_mentions` keeps anything in it
  # from pinging, so titles are only cut to length: escaping them would show
  # the backslashes if Discord does not read markdown there. Descriptions,
  # which do link, are escaped where they are built.
  defp message(embeds) do
    %{
      username: String.slice(Branding.friendly_platform_name(), 0, 80),
      allowed_mentions: %{parse: []},
      embeds: Enum.map(embeds, &embed/1)
    }
  end

  defp embed(embed) do
    embed
    |> Map.update(:title, nil, &String.slice(&1, 0, @max_title))
    |> Map.update(:description, nil, &(&1 && String.slice(&1, 0, @max_description)))
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp more_embed(0, _where), do: []
  defp more_embed(more, where), do: [%{description: "And #{more} more on #{where}.", color: @grey}]

  defp footer(parts) do
    case Enum.reject(parts, &(&1 in [nil, ""])) do
      [] -> nil
      parts -> %{text: parts |> Enum.join(" · ") |> String.slice(0, 2048)}
    end
  end

  defp listed(lines) do
    {shown, rest} = Enum.split(lines, @listed)
    shown = Enum.map(shown, &("• " <> &1))
    Enum.join(if(rest == [], do: shown, else: shown ++ ["and #{length(rest)} more"]), "\n")
  end

  defp product_name(event), do: get_in(event, ["product", "name"])

  defp product_names(events) do
    [events |> Enum.map(&product_name/1) |> Enum.reject(&is_nil/1) |> Enum.uniq() |> Enum.join(", ")]
  end

  defp device_name(event), do: get_in(event, ["device", "identifier"]) || "a device"

  defp device_link(event), do: link(device_name(event), Links.device(event))

  defp link(text, nil), do: escape(text)
  defp link(text, url), do: "[#{escape(text)}](#{url})"

  # Discord's markdown, escaped with a backslash, so text a device sent shows
  # as it was sent. Parentheses are left alone: with the brackets escaped
  # they cannot make a link. A dash only means something at the start of a
  # line.
  defp escape(text) do
    text
    |> to_string()
    |> String.replace(~r/[\\\\*_~`|>\[\]#<]/u, "\\\\\\0")
    |> String.replace(~r/^-/mu, "\\\\-")
  end

  defp truncate(text) do
    text = to_string(text)
    if String.length(text) > @max_text, do: String.slice(text, 0, @max_text) <> "…", else: text
  end
end
