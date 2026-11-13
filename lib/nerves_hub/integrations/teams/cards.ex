defmodule NervesHub.Integrations.Teams.Cards do
  @moduledoc """
  The Adaptive Cards NervesHub posts to Teams channels, each wrapped as the
  message a Workflows webhook takes.

  A batch of one kind of event becomes one card, as `NervesHub.Integrations.Slack.Messages`
  builds Slack messages, from the same event data: a single event gets a
  card of its own, and a burst gets a count and the first few devices.

  Text a device or a person typed goes into `TextRun`s, which Teams shows as
  it is: markdown in one is not rendered, so it cannot become a link or
  formatting. The links NervesHub makes are `Action.OpenUrl`s, on a button or
  on a run of text.

  A Workflows webhook's cards cannot call back, so there is no Reboot or
  Approve on them. A card says what happened and links to the page where it
  can be acted on.
  """

  alias NervesHub.Branding
  alias NervesHub.Integrations.Links

  @listed 10
  @shown 5
  @max_text 300

  @status_icons %{"unhealthy" => "🔴", "warning" => "🟡", "healthy" => "🟢", "unknown" => "⚪"}
  @level_icons %{"error" => "🔴", "warning" => "⚠️", "info" => "ℹ️"}

  @type message() :: %{required(String.t()) => term()}

  @doc "The card for a batch of events of one key (`NervesHub.Integrations.ChannelEvents`)."
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
      line([
        run("👋 "),
        run(
          "#{Branding.friendly_platform_name()} will post #{Enum.join(labels, ", ")} for #{org_name} here. This test was sent by #{user_name}."
        )
      ])
    ])
  end

  ## Health

  defp health([event]) do
    status = event["status"]

    message(
      [
        line([
          run("#{status_icon(status)} "),
          device(event, bold: true),
          run(" is now "),
          run(status, weight: "Bolder"),
          run(was(event["previous_status"]))
        ]),
        context([product_name(event), reasons(event)])
      ],
      open_device(event)
    )
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
        [
          run("#{status_icon(event["status"])} "),
          device(event),
          run(" #{event["status"]}#{was(event["previous_status"])}")
        ]
      end)

    message(
      [heading("#{length(changes)} devices changed health status: #{counts}") | listed(lines)] ++ [products(changes)]
    )
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

  defp status_icon(status), do: Map.get(@status_icons, status, "⚪")

  defp reasons(%{"status" => status, "reasons" => %{} = reasons}) do
    case Map.get(reasons, status) do
      %{} = metrics when map_size(metrics) > 0 ->
        metrics
        |> Enum.map_join(", ", fn {metric, details} -> "#{metric}#{threshold(details)}" end)
        |> truncate()

      _ ->
        nil
    end
  end

  defp reasons(_event), do: nil

  defp threshold(%{"threshold" => threshold}), do: " (threshold #{threshold})"
  defp threshold(_details), do: ""

  ## Updates

  defp update_failed([event]) do
    message(
      [
        line([
          run("❌ Update to "),
          run(target(event), weight: "Bolder"),
          run(" #{failure(event)} on "),
          device(event, bold: true),
          run(reason(event))
        ]),
        context([product_name(event), deployment_group(event), from(event)])
      ],
      open_device(event)
    )
  end

  defp update_failed(events) do
    lines = Enum.map(events, &[device(&1), run(" to #{target(&1)}: #{failure(&1)}#{reason(&1)}")])

    message([heading("❌ #{length(events)} updates failed") | listed(lines)] ++ [products(events)])
  end

  defp update_succeeded([event]) do
    message(
      [
        line([run("✅ "), device(event, bold: true), run(" updated to "), run(target(event), weight: "Bolder")]),
        context([product_name(event), deployment_group(event), from(event)])
      ],
      open_device(event)
    )
  end

  defp update_succeeded(events) do
    versions =
      events
      |> Enum.frequencies_by(&target/1)
      |> Enum.sort_by(fn {_version, count} -> -count end)
      |> Enum.map_join(", ", fn {version, count} -> "#{count} to #{version}" end)

    lines = Enum.map(events, &[device(&1), run(" to #{target(&1)}")])

    message([heading("✅ #{length(events)} devices updated: #{versions}") | listed(lines)] ++ [products(events)])
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

  defp reason(%{"reason" => reason}) when is_binary(reason) and reason != "", do: ": #{truncate(reason)}"
  defp reason(_event), do: ""

  defp deployment_group(%{"deployment_group" => %{"name" => name}}), do: "deployment group #{name}"
  defp deployment_group(_event), do: nil

  ## Errors

  defp errors([event], kind) do
    {icon, heading} =
      case kind do
        :created -> {"🚨", "New error in "}
        :reopened -> {"↩️", "Error reopened in "}
      end

    message(
      [
        line([
          run("#{icon} #{heading}"),
          run(product_name(event) || "a product", weight: "Bolder"),
          run(": "),
          run(truncate(get_in(event, ["error", "reason"]) || "an error"), font_type: "Monospace")
        ]),
        context([top_frame(event)])
      ],
      open("View the error", Links.error(event))
    )
  end

  defp errors(events, kind) do
    summary =
      case kind do
        :created -> "🚨 #{length(events)} new errors"
        :reopened -> "↩️ #{length(events)} errors reopened"
      end

    lines = Enum.map(events, &[link(String.slice(get_in(&1, ["error", "reason"]) || "", 0, 80), Links.error(&1))])

    message([heading(summary) | listed(lines)] ++ [products(events)])
  end

  defp top_frame(event) do
    case get_in(event, ["error", "top_frame"]) do
      nil -> nil
      frame -> truncate(frame)
    end
  end

  ## Deployment workflows

  # Each is its own section rather than a count: a few deployment groups
  # moving at once is still few enough to read.
  defp workflow(events, event) do
    shown = Enum.take(events, @shown)
    more = length(events) - length(shown)

    body =
      Enum.flat_map(shown, fn data ->
        [line(step_sentence(event, data)), context([product_name(data), release(data)])]
      end)

    body = if more > 0, do: body ++ [context(["And #{more} more on the deployment groups' pages."])], else: body

    actions =
      case shown do
        [data] -> open("Open in #{Branding.friendly_platform_name()}", Links.deployment_group(data))
        _ -> []
      end

    message(body, actions)
  end

  defp step_sentence(event, data) do
    step = step_runs(data)
    group = group_runs(data)

    case {event, get_in(data, ["user", "name"])} do
      {"started", nil} ->
        [run("▶️ ")] ++ step ++ [run(" started for ")] ++ group

      {"started", by} ->
        [run("🔁 #{by} retried ")] ++ step ++ [run(" for ")] ++ group

      {"awaiting_approval", _} ->
        [run("✋ ")] ++ group ++ [run(" is waiting for approval at ")] ++ step

      {"completed", nil} ->
        [run("✅ ")] ++ step ++ [run(" completed for ")] ++ group

      {"completed", by} ->
        [run("✅ #{by} approved ")] ++ step ++ [run(" for ")] ++ group

      {"skipped", nil} ->
        [run("⏩ ")] ++ step ++ [run(" was skipped for ")] ++ group

      {"skipped", by} ->
        [run("⏩ #{by} skipped ")] ++ step ++ [run(" for ")] ++ group

      {"failed", _} ->
        [run("❌ ")] ++
          step ++
          [run(" failed for ")] ++
          group ++
          [run("#{failed_devices(data)}. The rollout is stopped until the step is retried or skipped.")]
    end
  end

  defp step_runs(data) do
    [run(get_in(data, ["step", "name"]) || "a step", weight: "Bolder"), run(step_position(data))]
  end

  defp group_runs(data) do
    [link(get_in(data, ["deployment_group", "name"]) || "a deployment group", Links.deployment_group(data))]
  end

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

    body =
      Enum.flat_map(shown, fn event ->
        notification = event["notification"] || %{}
        icon = Map.get(@level_icons, notification["level"], "ℹ️")

        [
          line([run("#{icon} "), run(notification["title"] || "", weight: "Bolder")]),
          line([run(truncate(notification["message"] || ""))]),
          line(
            Enum.reject(
              [
                product_name(event) && run(product_name(event) <> " · ", subtle: true),
                link("Notifications", Links.notifications(event), subtle: true)
              ],
              &(&1 in [nil, false])
            )
          )
        ]
      end)

    body = if more > 0, do: body ++ [context(["And #{more} more on the products' Notifications pages."])], else: body

    message(body)
  end

  ## Building blocks

  defp message(body, actions \\ []) do
    card =
      %{
        "$schema" => "http://adaptivecards.io/schemas/adaptive-card.json",
        type: "AdaptiveCard",
        version: "1.4",
        body: Enum.reject(body, &is_nil/1),
        msteams: %{width: "Full"}
      }

    card = if actions == [], do: card, else: Map.put(card, :actions, actions)

    %{
      "type" => "message",
      "attachments" => [
        %{"contentType" => "application/vnd.microsoft.card.adaptive", "contentUrl" => nil, "content" => card}
      ]
    }
  end

  defp heading(text), do: line([run(text, weight: "Bolder")])

  defp line(inlines), do: %{type: "RichTextBlock", inlines: inlines}

  # Teams leaves out an element with nothing in it, but an empty text run is
  # still noise in the card's JSON, so a context with nothing to say is left
  # out (`message/2`).
  defp context(parts) do
    case Enum.reject(parts, &(&1 in [nil, ""])) do
      [] -> nil
      parts -> %{type: "RichTextBlock", inlines: [run(Enum.join(parts, " · "), subtle: true, size: "Small")]}
    end
  end

  defp products(events) do
    events
    |> Enum.map(&product_name/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.join(", ")
    |> List.wrap()
    |> context()
  end

  defp listed(lines) do
    {shown, rest} = Enum.split(lines, @listed)
    shown = Enum.map(shown, &line([run("• ") | &1]))

    if rest == [], do: shown, else: shown ++ [line([run("and #{length(rest)} more")])]
  end

  defp run(text, opts \\ []) do
    Enum.reduce(opts, %{type: "TextRun", text: to_string(text)}, fn
      {:weight, weight}, run -> Map.put(run, :weight, weight)
      {:subtle, true}, run -> Map.put(run, :isSubtle, true)
      {:size, size}, run -> Map.put(run, :size, size)
      {:font_type, font}, run -> Map.put(run, :fontType, font)
      {:url, url}, run -> Map.put(run, :selectAction, %{type: "Action.OpenUrl", url: url})
      _other, run -> run
    end)
  end

  defp link(text, nil, opts), do: run(text, opts)
  defp link(text, url, opts), do: run(text, [{:url, url} | opts])
  defp link(text, url), do: link(text, url, [])

  defp device(event, opts \\ []) do
    identifier = get_in(event, ["device", "identifier"]) || "a device"
    opts = if opts[:bold], do: [weight: "Bolder"], else: []
    link(identifier, Links.device(event), opts)
  end

  defp open_device(event), do: open("Open in #{Branding.friendly_platform_name()}", Links.device(event))

  defp open(_title, nil), do: []
  defp open(title, url), do: [%{type: "Action.OpenUrl", title: title, url: url}]

  defp product_name(event), do: get_in(event, ["product", "name"])

  defp truncate(text) do
    text = to_string(text)
    if String.length(text) > @max_text, do: String.slice(text, 0, @max_text) <> "…", else: text
  end
end
