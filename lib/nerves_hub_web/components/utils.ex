defmodule NervesHubWeb.Components.Utils do
  use NervesHubWeb, :component

  alias NervesHub.Accounts.OrgRole
  alias NervesHub.Accounts.Permissions
  alias Phoenix.HTML.FormField

  @doc """
  Options for a role select: the built-in roles, then the org's custom roles
  when it has any. Read the chosen value back with `role_choice/1`'s format:
  a built-in role's name, or `"custom:<id>"`.
  """
  def role_options(custom_roles \\ []) do
    built_in = for role <- Permissions.built_in_roles(), do: {role_name(role), Atom.to_string(role)}

    case custom_roles do
      [] ->
        built_in

      custom_roles ->
        [{"Built-in roles", built_in}, {"Custom roles", Enum.map(custom_roles, &{&1.name, "custom:#{&1.id}"})}]
    end
  end

  @doc """
  The `role_options/1` value for the role a member holds or an invite offers.

  Falls back to view rather than letting a select land on its first option,
  which is admin.
  """
  def role_choice(%{org_role: %OrgRole{id: org_role_id}}), do: "custom:#{org_role_id}"
  def role_choice(%{org_role_id: nil, role: role}) when not is_nil(role), do: Atom.to_string(role)
  def role_choice(_), do: "view"

  @doc """
  A role's name for display. Takes a built-in role, a custom `OrgRole`, or a
  member or invite, for the role it holds.
  """
  def role_name(%OrgRole{name: name}), do: name
  def role_name(%{org_role_id: nil, role: role}), do: role_name(role)
  def role_name(%{org_role: %OrgRole{} = org_role}), do: role_name(org_role)
  def role_name(role) when is_atom(role) and not is_nil(role), do: role |> Atom.to_string() |> String.capitalize()
  def role_name(_), do: "No role"

  @doc """
  A number for display. Elixir's default float rendering flips to scientific
  notation at 10^4 (9000.0 prints as "9.0e3"), which is wrong everywhere a
  threshold or metric value faces a person. Whole floats print as integers,
  fractions keep up to four decimals. Anything that is not a number — a
  jsonb value that predates validation — passes through untouched, so a
  template can render whatever is there.
  """
  def format_number(number) when is_integer(number), do: Integer.to_string(number)

  def format_number(number) when is_float(number) do
    if number == trunc(number) do
      number |> trunc() |> Integer.to_string()
    else
      number
      |> :erlang.float_to_binary(decimals: 4)
      |> String.trim_trailing("0")
      |> String.trim_trailing(".")
    end
  end

  def format_number(not_a_number), do: not_a_number

  @doc """
  A metric reading for display: floats rounded to one decimal, formatted by
  `format_number/1`; anything else untouched.
  """
  def nice_round(value) when is_float(value), do: format_number(Float.round(value, 1))
  def nice_round(value), do: format_number(value)

  @doc """
  A measurement period in seconds as a compact human string: "45s", "30m",
  "6h", "1d", "1m 30s".
  """
  def format_period(seconds) when seconds < 60, do: "#{seconds}s"
  def format_period(seconds) when rem(seconds, 86_400) == 0, do: "#{div(seconds, 86_400)}d"
  def format_period(seconds) when rem(seconds, 3600) == 0, do: "#{div(seconds, 3600)}h"
  def format_period(seconds) when rem(seconds, 60) == 0, do: "#{div(seconds, 60)}m"
  def format_period(seconds), do: "#{div(seconds, 60)}m #{rem(seconds, 60)}s"

  def format_serial(big_long_integer) when is_integer(big_long_integer) do
    big_long_integer
    |> Integer.to_string(16)
    |> to_charlist()
    |> Enum.chunk_every(2)
    |> Enum.join(":")
  end

  def format_serial(serial_str) when is_binary(serial_str) do
    String.to_integer(serial_str)
    |> format_serial()
  end

  def cpu_temp_to_status(temp) do
    case temp do
      temp when temp < 60 -> ""
      temp when temp < 90 -> "warn"
      _ -> "danger"
    end
  end

  def usage_percent_to_status(usage) do
    case usage do
      usage when usage < 80 -> ""
      usage when usage < 90 -> "warn"
      _ -> "danger"
    end
  end

  def disk_usage(%{"disk_available_kb" => available, "disk_total_kb" => total, "disk_used_percentage" => percentage}) do
    usage = (total - available) / 1000

    "#{Sizeable.filesize(usage * 1024)} of #{Sizeable.filesize(available * 1024)} (#{round(percentage)}%)"
  end

  def tags_to_string(%FormField{} = field) do
    tags_to_string(field.value)
  end

  def tags_to_string(%{tags: tags}), do: tags_to_string(tags)
  def tags_to_string(tags) when is_list(tags), do: Enum.join(tags, ", ")
  def tags_to_string(tags), do: tags
end
