defmodule NervesHub.ProductNotifications.Copy do
  @moduledoc """
  Writes a notification's title and message from its kind and metadata.

  The copy is written when it's shown, so changing it here changes old
  notifications too. `card/1` is for the notifications list, and leaves out
  what the card shows beside it (a device, a webhook). `full/2` names it, for
  where the notification goes without that, such as a Slack or Teams
  channel, and is what `ProductNotifications` stores as `title` and
  `message`. `rollup/4` writes the card for a kind raised on many devices. A
  notification whose metadata lacks something its kind's copy needs, such as
  one raised before that was stored or one with no kind, is shown with the
  title and message it was stored with.
  """

  alias NervesHub.Branding
  alias NervesHub.Devices.ReportedMetadata
  alias NervesHub.Products.Notification

  @type text :: %{title: String.t(), message: String.t()}

  # The metadata each kind's copy reads.
  @needs %{
    chat_webhook_disabled: ~w(channel service reason),
    connecting_code_failure: ~w(identifier reason),
    device_bulk_create: ~w(created failed),
    duplicate_device_identifier: ~w(identifier),
    extension_failure: ~w(identifier extension reason),
    invalid_device_metadata: ~w(identifier reasons count),
    missing_firmware_metadata: ~w(identifier),
    oversized_metric_keys: ~w(identifier example_key count max_bytes),
    slack_subscription_disabled: ~w(channel reason),
    soft_deleted_device: ~w(identifier),
    too_many_metrics: ~w(identifier reported max_keys),
    update_mode_revert_failed: ~w(identifier),
    webhook_disabled: ~w(host reason),
    workflow_halted: ~w(deployment_group step_number step reason),
    wrong_websocket_host: ~w(identifier host)
  }

  @doc """
  The notification as its card in the notifications list says it, without
  what it's about.
  """
  @spec card(Notification.t()) :: text()
  def card(%Notification{kind: kind, metadata: metadata} = notification) do
    metadata = stringify(metadata)

    if writable?(kind, metadata) do
      %{title: title(kind, metadata), message: message(kind, metadata, :card)}
    else
      %{title: notification.title, message: notification.message}
    end
  end

  @doc """
  The notification as it's said away from the notifications list, naming
  what it's about.

  What `ProductNotifications` stores as `title` and `message` when it raises
  one.
  """
  @spec full(Notification.kind(), map()) :: text()
  def full(kind, metadata) do
    metadata = stringify(metadata)
    %{title: title(kind, metadata), message: message(kind, metadata, :full)}
  end

  @doc """
  The card for `count` notifications of one kind, about `devices` devices.

  `latest` is the most recent of them, for details they share, such as the
  host they should have connected to. A card of one notification is that
  notification's `card/1`.
  """
  @spec rollup(Notification.kind(), pos_integer(), pos_integer(), Notification.t()) :: text()
  def rollup(_kind, _devices, 1, latest), do: card(latest)

  def rollup(:extension_failure, 1, count, _latest) do
    %{
      title: "A device had #{delimited(count)} extension failures.",
      message:
        "The extensions stay on in #{platform()}, but won't work on this device until the causes are fixed, " <>
          "usually in its firmware."
    }
  end

  # Every other kind is raised once per device, so one device is one notification.
  def rollup(_kind, 1, _count, latest), do: card(latest)

  def rollup(kind, devices, _count, %Notification{metadata: metadata}) do
    rolled_up(kind, devices, stringify(metadata))
  end

  @doc """
  What sets one device's notification apart from the others rolled up with
  it, for its row in the card: the extension that failed, how many metrics
  it sent.

  `nil` when nothing does.
  """
  @spec detail(Notification.t()) :: String.t() | nil
  def detail(%Notification{kind: kind, metadata: metadata}), do: detail(kind, stringify(metadata))

  defp detail(:extension_failure, %{"extension" => extension, "reason" => reason}) when is_binary(reason),
    do: "#{extension}: #{reason}"

  defp detail(:extension_failure, %{"extension" => extension}), do: extension

  defp detail(:invalid_device_metadata, %{"reasons" => ["not_an_object"]}), do: "not an object"

  defp detail(:invalid_device_metadata, %{"count" => count}),
    do: "#{delimited(count)} #{plural(count, "key", "keys")} dropped"

  defp detail(:oversized_metric_keys, %{"count" => count}),
    do: "#{delimited(count)} long #{plural(count, "name", "names")}"

  defp detail(:too_many_metrics, %{"reported" => reported}), do: "#{delimited(reported)} metrics"
  defp detail(_kind, _metadata), do: nil

  defp writable?(nil, _metadata), do: false
  defp writable?(kind, metadata), do: Enum.all?(Map.fetch!(@needs, kind), &Map.has_key?(metadata, &1))

  # Metadata reads back from the database with string keys, and comes back
  # from an insert with the atom keys it was written with.
  defp stringify(metadata) when is_map(metadata), do: Map.new(metadata, fn {key, value} -> {to_string(key), value} end)
  defp stringify(_metadata), do: %{}

  ## Titles. The same on the card and away from it, so they never name what
  ## the notification is about.

  defp title(:chat_webhook_disabled, m), do: "#{m["service"]} notifications were turned off."
  defp title(:connecting_code_failure, _m), do: "A device could not run its connecting code."
  defp title(:device_bulk_create, _m), do: "A device import finished."
  defp title(:duplicate_device_identifier, _m), do: "A device tried to connect with an identifier already in use."
  defp title(:extension_failure, _m), do: "A device could not start an extension."
  defp title(:invalid_device_metadata, _m), do: "A device reported metadata #{platform()} couldn't store."
  defp title(:missing_firmware_metadata, _m), do: "A device connected without firmware metadata."
  defp title(:oversized_metric_keys, _m), do: "A device reported metric names too long to store."
  defp title(:slack_subscription_disabled, _m), do: "Slack notifications were turned off."
  defp title(:soft_deleted_device, _m), do: "A soft-deleted device was permanently deleted."
  defp title(:too_many_metrics, _m), do: "A device reported more metrics than #{platform()} stores."
  defp title(:update_mode_revert_failed, _m), do: "A device could not be returned to automatic updates."
  defp title(:webhook_disabled, _m), do: "A webhook was turned off."

  defp title(:workflow_halted, %{"reason" => "failed"}),
    do: "A deployment workflow stopped after devices failed to update."

  defp title(:workflow_halted, _m), do: "A deployment workflow is waiting for approval."
  defp title(:wrong_websocket_host, _m), do: "A device connected to the wrong host."

  ## Messages. `:card` leaves out what the card shows beside it, `:full`
  ## names it.

  defp message(:chat_webhook_disabled, m, form) do
    to = if form == :full, do: " to the #{m["service"]} channel #{m["channel"]}", else: ""

    "#{platform()} stopped posting#{to} " <>
      "because #{m["reason"]}. Once the webhook is fixed, turn the channel back on in the organization's " <>
      "Integrations settings, or give it the webhook's new URL."
  end

  defp message(:connecting_code_failure, m, form) do
    "#{it(form, m)} could not run the connecting code it was sent when it connected#{reason_clause(m)}. " <>
      "A device's connecting code combines its own, its deployment group's and its release's, " <>
      "and every device sent the same code adds to this count."
  end

  defp message(:device_bulk_create, %{"created" => created, "failed" => failed}, _form) do
    case {created, failed} do
      {0, 0} ->
        "The manifest had no devices in it."

      {1, 0} ->
        "1 device was added, along with its certificate."

      {created, 0} ->
        "#{delimited(created)} devices were added, along with their certificates."

      {0, 1} ->
        "The only device in the manifest could not be added. Check that the manifest is valid."

      {0, failed} ->
        "None of the #{delimited(failed)} devices in the manifest could be added. Check that the manifest is valid."

      {created, failed} ->
        "#{delimited(created)} #{plural(created, "device was", "devices were")} added, and #{delimited(failed)} could not be. " <>
          "Check the manifest for the #{plural(failed, "one", "ones")} that failed."
    end
  end

  defp message(:duplicate_device_identifier, m, form) do
    tried = if form == :full, do: "A device tried to connect as '#{m["identifier"]}'. ", else: ""

    tried <>
      "Another device already has this identifier, possibly one that was soft-deleted. " <>
      "Remove that device, or give the new one a different identifier."
  end

  defp message(:extension_failure, m, form) do
    "#{it(form, m)} could not start the #{m["extension"]} extension#{reason_clause(m)}. " <>
      "It stays on in #{platform()}, but won't work on this device until the cause is fixed, " <>
      "usually in the device's firmware."
  end

  defp message(:invalid_device_metadata, %{"reasons" => ["not_an_object"]} = m, form) do
    "#{it(form, m)} sent metadata that wasn't an object of names and values, so none of it was stored. " <>
      "Check the metadata its firmware reports."
  end

  defp message(:invalid_device_metadata, m, form) do
    count = m["count"]
    such_as = if key = m["example_key"], do: ", such as '#{key}'", else: ""

    "#{it(form, m)} sent metadata with #{metadata_problems(m["reasons"])}. " <>
      "#{delimited(count)} #{plural(count, "key was", "keys were")} dropped#{such_as}, and the rest was kept."
  end

  defp message(:missing_firmware_metadata, m, form) do
    "#{it(form, m)} reported no firmware UUID (`nerves_fw_uuid` in its U-Boot environment), " <>
      "so #{platform()} can't tell which firmware it's running. Check the device's firmware."
  end

  defp message(:oversized_metric_keys, m, form) do
    count = m["count"]

    "#{it(form, m)} sent #{delimited(count)} #{plural(count, "metric", "metrics")} with names longer than " <>
      "#{m["max_bytes"]} bytes, starting with '#{String.slice(m["example_key"], 0, 64)}'. " <>
      "Those readings were dropped and the rest of the report was kept. " <>
      "Shorten the metric names the device reports."
  end

  defp message(:slack_subscription_disabled, m, form) do
    to = if form == :full, do: " to ##{m["channel"]}", else: ""

    "#{platform()} stopped posting#{to} because #{m["reason"]}. " <>
      "Once that's fixed, turn the channel back on in the organization's Integrations settings."
  end

  defp message(:soft_deleted_device, m, form) do
    "#{it(form, m)} was soft-deleted, and soft-deleted devices are permanently deleted after two weeks."
  end

  defp message(:too_many_metrics, m, form) do
    max = m["max_keys"]

    "#{it(form, m)} sent #{delimited(m["reported"])} metrics in one report, and #{platform()} stores at most #{delimited(max)}. " <>
      "The first #{delimited(max)} metric names in alphabetical order were kept, so the same readings are dropped each time."
  end

  defp message(:update_mode_revert_failed, m, form) do
    "#{it(form, m)} is set to manage its own updates, but its firmware is too old to do that, " <>
      "and #{platform()} couldn't switch it back. It gets no firmware until you set its update mode " <>
      "or send it firmware by hand."
  end

  defp message(:webhook_disabled, m, form) do
    to = if form == :full, do: " to #{m["host"]}", else: ""

    "#{platform()} stopped sending events#{to} because #{m["reason"]}. " <>
      "Once the endpoint is fixed, turn the webhook back on in the organization's Integrations settings."
  end

  defp message(:workflow_halted, m, form) do
    step = "Step #{m["step_number"]} ('#{m["step"]}')"
    step = if form == :full, do: "#{step} of the workflow for deployment group '#{m["deployment_group"]}'", else: step

    case m do
      %{"reason" => "failed"} ->
        failed = m["failed_count"] || 0

        "#{step} failed: #{delimited(failed)} #{plural(failed, "device", "devices")} could not take the update. " <>
          "No more devices will update to this release until the step is retried or skipped."

      _awaiting_approval ->
        "#{step} needs approving before the rollout continues. " <>
          "No more devices will update to this release until it's approved or skipped."
    end
  end

  defp message(:wrong_websocket_host, m, form) do
    host = m["host"]

    "#{it(form, m)} connected to the management host instead of #{host}, and was redirected. " <>
      "Point the device's configuration at #{host}."
  end

  ## Many devices at once.

  defp rolled_up(:duplicate_device_identifier, count, _m) do
    %{
      title: "#{delimited(count)} devices tried to connect with identifiers already in use.",
      message:
        "Other devices already have these identifiers, possibly ones that were soft-deleted. " <>
          "Remove those devices, or give the new ones different identifiers."
    }
  end

  defp rolled_up(:extension_failure, count, _m) do
    %{
      title: "#{delimited(count)} devices could not start an extension.",
      message:
        "The extensions stay on in #{platform()}, but won't work on these devices until the cause is fixed, " <>
          "usually in their firmware."
    }
  end

  defp rolled_up(:invalid_device_metadata, count, _m) do
    %{
      title: "#{delimited(count)} devices reported metadata #{platform()} couldn't store.",
      message:
        "Keys #{platform()} sets itself, names or values too long to store, and keys past the first " <>
          "#{ReportedMetadata.max_keys()} were dropped, and the rest of each device's metadata was kept."
    }
  end

  defp rolled_up(:missing_firmware_metadata, count, _m) do
    %{
      title: "#{delimited(count)} devices connected without firmware metadata.",
      message:
        "They reported no firmware UUID (`nerves_fw_uuid` in their U-Boot environment), " <>
          "so #{platform()} can't tell which firmware they're running."
    }
  end

  defp rolled_up(:oversized_metric_keys, count, m) do
    longer_than = if max = m["max_bytes"], do: "longer than #{max} bytes", else: "too long to store"

    %{
      title: "#{delimited(count)} devices reported metric names too long to store.",
      message: "Readings with names #{longer_than} were dropped, and the rest of each report was kept."
    }
  end

  defp rolled_up(:soft_deleted_device, count, _m) do
    %{
      title: "#{delimited(count)} soft-deleted devices were permanently deleted.",
      message: "Soft-deleted devices are permanently deleted after two weeks."
    }
  end

  defp rolled_up(:too_many_metrics, count, m) do
    kept = if max = m["max_keys"], do: "Only the first #{delimited(max)} metric names", else: "Only some of the metrics"

    %{
      title: "#{delimited(count)} devices reported more metrics than #{platform()} stores.",
      message: "#{kept} in each report, in alphabetical order, were kept."
    }
  end

  defp rolled_up(:update_mode_revert_failed, count, _m) do
    %{
      title: "#{delimited(count)} devices could not be returned to automatic updates.",
      message:
        "They're set to manage their own updates, but their firmware is too old to do that. " <>
          "They get no firmware until you set their update mode or send them firmware by hand."
    }
  end

  defp rolled_up(:wrong_websocket_host, count, m) do
    instead_of = if host = m["host"], do: " instead of #{host}", else: ""

    %{
      title: "#{delimited(count)} devices connected to the wrong host.",
      message: "They connected to the management host#{instead_of}, and were redirected."
    }
  end

  # Why `ReportedMetadata.trim/1` dropped keys, in the order it checks.
  defp metadata_problems(reasons) when is_list(reasons) do
    reasons
    |> Enum.flat_map(fn
      "reserved" ->
        ["names #{platform()} sets itself"]

      "too_long" ->
        ["names over #{ReportedMetadata.max_key_bytes()} bytes or values over #{ReportedMetadata.max_value_bytes()}"]

      "too_many" ->
        ["more than #{ReportedMetadata.max_keys()} keys"]

      _unknown ->
        []
    end)
    |> case do
      [] -> "keys it couldn't store"
      [one] -> one
      problems -> Enum.join(Enum.drop(problems, -1), ", ") <> " and " <> List.last(problems)
    end
  end

  defp metadata_problems(_reasons), do: "keys it couldn't store"

  defp it(:card, _m), do: "It"
  defp it(:full, m), do: "The device '#{m["identifier"]}'"

  defp reason_clause(%{"reason" => reason}) when is_binary(reason) and reason != "", do: ": #{reason}"
  defp reason_clause(_m), do: ""

  # Anything but an integer, such as a count missing from older metadata,
  # passes through as it is.
  defp delimited(number) when is_integer(number), do: Number.Delimit.number_to_delimited(number, precision: 0)
  defp delimited(number), do: number

  defp plural(1, one, _many), do: one
  defp plural(_count, _one, many), do: many

  defp platform(), do: Branding.friendly_platform_name()
end
