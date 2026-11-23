defmodule NervesHubWeb.Components.AuditLogDescription do
  @moduledoc """
  An audit log entry's description, with the records it names linked.

  An entry written from a `NervesHub.AuditLogs.Template` names each user,
  device, deployment group, firmware and archive as it is now, from the
  records `NervesHub.AuditLogs.load_references/3` loaded for the page, and
  links to the ones the viewer can open. A record that is gone, or that the
  viewer can't see, keeps the name it had when the entry was written, as plain
  text. An entry written before templates shows its description as it is.

  Each reference stands out from the text around it, linked or not, and
  carries `data-ref` naming its type (`user`, `device`, `deployment_group`,
  `firmware` or `archive`), so a type can be styled on its own.

  Every part is rendered as text, a span or a link, never as raw HTML, so the
  text a device sends can't add markup.
  """
  use NervesHubWeb, :component

  alias NervesHub.Accounts.Scope
  alias NervesHub.Accounts.User
  alias NervesHub.Archives.Archive
  alias NervesHub.AuditLogs.Template
  alias NervesHub.Devices.Device
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.ManagedDeployments.DeploymentGroup

  attr(:entry, :map, required: true, doc: "An `NervesHub.AuditLogs.AuditLog`.")
  attr(:references, :map, default: %{}, doc: "From `NervesHub.AuditLogs.load_references/3`.")
  attr(:scope, Scope, required: true)
  attr(:current, :any, default: nil, doc: "The record whose page this is, named without a link to itself.")

  def description(%{entry: %{template: nil}} = assigns) do
    ~H"{@entry.description}"
  end

  def description(assigns) do
    %{entry: entry, references: references, scope: scope, current: current} = assigns
    values = entry.template_values || %{}

    parts =
      for part <- Template.parse(entry.template) do
        case part do
          {:placeholder, name} -> placeholder(Map.get(values, name), name, references, scope, key(current))
          text -> {:text, text}
        end
      end

    assigns = assign(assigns, :parts, parts)

    ~H"<.part :for={part <- @parts} part={part} />"
  end

  defp part(%{part: {:text, text}} = assigns) do
    assigns = assign(assigns, :text, text)

    ~H"{@text}"
  end

  defp part(%{part: {:reference, type, text, nil}} = assigns) do
    assigns = assign(assigns, type: type, text: text)

    ~H|<span data-ref={@type} class="font-medium text-content-strong">{@text}</span>|
  end

  defp part(%{part: {:reference, type, text, path}} = assigns) do
    assigns = assign(assigns, type: type, text: text, path: path)

    ~H|<.link navigate={@path} data-ref={@type} class="font-medium text-content-strong hover:underline">{@text}</.link>|
  end

  # A reference shows the record as it is now, linked when the viewer can open
  # it, or the name it had when the entry was written when it's gone or out of
  # the viewer's sight.
  defp placeholder(%{"type" => type, "id" => id, "name" => stored}, _name, references, scope, current) do
    case Map.fetch(references, {type, id}) do
      {:ok, record} ->
        path = if {type, id} != current, do: link_path(record, scope)
        {:reference, type, name(record), path}

      :error ->
        {:reference, type, stored, nil}
    end
  end

  defp placeholder(text, _name, _references, _scope, _current) when is_binary(text), do: {:text, text}

  # A placeholder with no stored value, which only a template changed after the
  # entry was written could have.
  defp placeholder(_value, name, _references, _scope, _current), do: {:text, "%{#{name}}"}

  defp name(%User{name: name}), do: name
  defp name(%Device{identifier: identifier}), do: identifier
  defp name(%DeploymentGroup{name: name}), do: name
  defp name(%Firmware{uuid: uuid}), do: uuid
  defp name(%Archive{uuid: uuid}), do: uuid

  # No page shows a user. A product that has been deleted has no pages left.
  defp link_path(%User{}, _scope), do: nil
  defp link_path(%{product: nil}, _scope), do: nil

  defp link_path(%Device{} = device, %Scope{org: org}), do: ~p"/org/#{org}/#{device.product}/devices/#{device}"

  # Deployment group, firmware and archive pages are closed to a member who
  # sees only some of the org's devices (`NervesHubWeb.Mounts.RequireEveryDevice`).
  defp link_path(record, scope) do
    if !Scope.devices_limited?(scope), do: product_path(record, scope.org)
  end

  defp product_path(%DeploymentGroup{product: product} = group, org),
    do: ~p"/org/#{org}/#{product}/deployment_groups/#{group}"

  defp product_path(%Firmware{product: product} = firmware, org), do: ~p"/org/#{org}/#{product}/firmware/#{firmware}"
  defp product_path(%Archive{product: product} = archive, org), do: ~p"/org/#{org}/#{product}/archives/#{archive}"

  defp key(%Device{id: id}), do: {"device", id}
  defp key(%DeploymentGroup{id: id}), do: {"deployment_group", id}
  defp key(_record), do: nil
end
