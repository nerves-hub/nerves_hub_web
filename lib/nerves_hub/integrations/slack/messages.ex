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

  A message about one device carries buttons (`device_buttons/3`). A
  summary of many devices has none: acting on a list from one click is a
  different thing. A workflow waiting for approval carries Approve, and a
  failed workflow step Retry and Skip.
  """

  alias NervesHub.Branding
  alias NervesHub.Integrations.Links

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
    text =
      "#{escape(Branding.friendly_platform_name())} will post #{Enum.join(labels, ", ")} for #{escape(org_name)} here. This test was sent by #{escape(user_name)}."

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
              context([product_name(event), reasons(event)]),
              device_actions(event)
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
          context([product_name(event), deployment_group(event), from(event)]),
          device_actions(event)
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

  defp error_url(event), do: Links.error(event)

  ## Deployment workflows

  # Each is its own section, with its own buttons, rather than a count: a
  # few deployment groups moving at once is still few enough to read, and
  # each one waiting on somebody needs its own Approve or Retry.
  @steps_listed 5

  defp workflow(events, event) do
    shown = Enum.take(events, @steps_listed)
    more = length(events) - length(shown)

    blocks =
      Enum.flat_map(shown, fn data ->
        [
          section(step_heading(event, data, :mrkdwn)),
          context([product_name(data), release(data)]),
          step_actions(event, data)
        ]
      end)

    blocks =
      if more > 0 do
        blocks ++ [context(["And #{more} more on the deployment groups' pages."])]
      else
        blocks
      end

    text =
      case shown do
        [data] -> step_heading(event, data, :plain)
        _ -> "#{length(events)} workflow steps #{plural_verb(event)}"
      end

    %{text: text, blocks: blocks(blocks)}
  end

  # `:mrkdwn` links the deployment group, stresses the step and leads with an
  # icon; `:plain` is the same sentence for notifications, which show no
  # formatting.
  defp step_heading(event, data, :mrkdwn) do
    {icon, sentence} = step_sentence(event, step_name(data, :mrkdwn), deployment_group_name(data, :mrkdwn), data)
    "#{icon} #{sentence}"
  end

  defp step_heading(event, data, :plain) do
    {_icon, sentence} = step_sentence(event, step_name(data, :plain), deployment_group_name(data, :plain), data)
    sentence
  end

  defp step_sentence(event, step, group, data) do
    case {event, get_in(data, ["user", "name"])} do
      {"started", nil} ->
        {":arrow_forward:", "#{step} started for #{group}"}

      {"started", by} ->
        {":repeat:", "#{escape(by)} retried #{step} for #{group}"}

      {"awaiting_approval", _} ->
        {":raised_hand:", "#{group} is waiting for approval at #{step}"}

      {"completed", nil} ->
        {":white_check_mark:", "#{step} completed for #{group}"}

      {"completed", by} ->
        {":white_check_mark:", "#{escape(by)} approved #{step} for #{group}"}

      {"skipped", nil} ->
        {":fast_forward:", "#{step} was skipped for #{group}"}

      {"skipped", by} ->
        {":fast_forward:", "#{escape(by)} skipped #{step} for #{group}"}

      {"failed", _} ->
        {":x:",
         "#{step} failed for #{group}#{failed_devices(data)}. The rollout is stopped until the step is retried or skipped."}
    end
  end

  defp plural_verb("awaiting_approval"), do: "waiting for approval"
  defp plural_verb(event), do: event

  defp step_name(data, format) do
    name = escape(get_in(data, ["step", "name"]) || "a step")
    of = step_position(data)
    if format == :mrkdwn, do: "*#{name}*#{of}", else: "#{name}#{of}"
  end

  defp step_position(data) do
    case {get_in(data, ["step", "number"]), get_in(data, ["workflow", "steps"])} do
      {number, steps} when is_integer(number) and is_integer(steps) -> " (step #{number} of #{steps})"
      _ -> ""
    end
  end

  defp deployment_group_name(data, format) do
    case {get_in(data, ["deployment_group", "name"]), format, deployment_group_url(data)} do
      {nil, _format, _url} -> "a deployment group"
      {name, :mrkdwn, url} when is_binary(url) -> "<#{url}|#{escape(name)}>"
      {name, _format, _url} -> escape(name)
    end
  end

  defp failed_devices(%{"failed_devices" => 1}), do: ": 1 device could not take the update"

  defp failed_devices(%{"failed_devices" => count}) when is_integer(count),
    do: ": #{count} devices could not take the update"

  defp failed_devices(_data), do: ""

  defp release(data) do
    number = get_in(data, ["release", "number"])

    case get_in(data, ["release", "firmware", "version"]) do
      version when is_binary(version) -> "release #{number}, firmware #{escape(version)}"
      _ -> number && "release #{number}"
    end
  end

  # Approve on a workflow waiting for approval, Retry and Skip on a step that
  # failed. Like the device buttons, a button carries only the step's id, and
  # `NervesHubWeb.Integrations.Slack.WorkflowSteps` works out the rest when it is clicked.
  defp step_actions(event, data) when event in ["awaiting_approval", "failed"] do
    with id when is_integer(id) <- get_in(data, ["step", "id"]),
         url when is_binary(url) <- deployment_group_url(data) do
      name = get_in(data, ["step", "name"]) || "this step"

      buttons =
        case event do
          "awaiting_approval" ->
            [
              step_button("workflow_step.approve", "Approve", id, "primary", %{
                title: "Approve #{name}?",
                text: "The rollout carries on with the next step.",
                confirm: "Approve"
              })
            ]

          "failed" ->
            [
              step_button("workflow_step.retry", "Retry", id, "primary", %{
                title: "Retry #{name}?",
                text: "Its failed devices are let out of the penalty box and offered the update again.",
                confirm: "Retry"
              }),
              step_button("workflow_step.skip", "Skip", id, "danger", %{
                title: "Skip #{name}?",
                text: "Its devices are left to the steps after it, and the rollout carries on.",
                confirm: "Skip"
              })
            ]
        end

      %{type: "actions", elements: buttons ++ [open_button("deployment_group.open", url)]}
    else
      _ -> nil
    end
  end

  defp step_actions(_event, _data), do: nil

  defp step_button(action_id, label, step_id, style, confirm) do
    %{
      type: "button",
      action_id: action_id,
      text: plain(label),
      value: Integer.to_string(step_id),
      style: style,
      confirm: %{
        title: plain(String.slice(confirm.title, 0, 100)),
        text: %{type: "mrkdwn", text: confirm.text},
        confirm: plain(confirm.confirm),
        deny: plain("Cancel"),
        style: style
      }
    }
  end

  defp open_button(action_id, url) do
    %{
      type: "button",
      action_id: action_id,
      text: plain(String.slice("Open in #{Branding.friendly_platform_name()}", 0, 75)),
      url: url
    }
  end

  defp deployment_group_url(data), do: Links.deployment_group(data)

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
        [event] -> escape(get_in(event, ["notification", "title"]) || "A product notification")
        _ -> "#{length(events)} product notifications"
      end

    %{text: text, blocks: blocks(blocks)}
  end

  ## Buttons

  defp device_actions(event) do
    with org when is_binary(org) <- get_in(event, ["org", "name"]),
         product when is_binary(product) <- get_in(event, ["product", "name"]),
         identifier when is_binary(identifier) <- get_in(event, ["device", "identifier"]) do
      device_buttons(org, product, identifier)
    else
      _ -> nil
    end
  end

  @doc """
  The buttons for one device: Open in NervesHub, and Identify and Reboot,
  which `NervesHubWeb.Integrations.Slack.Actions` carries out. The identifier is all a
  button carries: who clicks it, and whether they may, is worked out when the
  click arrives.
  """
  @spec device_buttons(String.t(), String.t(), String.t()) :: %{type: String.t(), elements: [map(), ...]}
  def device_buttons(org_name, product_name, identifier) do
    %{
      type: "actions",
      elements: [
        open_button("device.open", device_url(org_name, product_name, identifier)),
        %{type: "button", action_id: "device.identify", text: plain("Identify"), value: identifier},
        %{
          type: "button",
          action_id: "device.reboot",
          text: plain("Reboot"),
          value: identifier,
          style: "danger",
          confirm: %{
            title: plain(String.slice("Reboot #{identifier}?", 0, 100)),
            text: %{type: "mrkdwn", text: "The device restarts straight away."},
            confirm: plain("Reboot"),
            deny: plain("Cancel"),
            style: "danger"
          }
        }
      ]
    }
  end

  defp plain(text), do: %{type: "plain_text", text: text}

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
    case device_url(event) do
      nil -> device_label(event)
      url -> "<#{url}|#{escape(get_in(event, ["device", "identifier"]))}>"
    end
  end

  defp device_url(event), do: Links.device(event)

  @doc "The device's page in NervesHub (`NervesHub.Integrations.Links.device/3`)."
  @spec device_url(String.t(), String.t(), String.t()) :: String.t()
  def device_url(org_name, product_name, identifier), do: Links.device(org_name, product_name, identifier)

  defp notifications_url(event), do: Links.notifications(event)

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
