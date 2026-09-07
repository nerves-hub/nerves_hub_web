defmodule NervesHub.Accounts.User.DisplayPreferencesTest do
  use ExUnit.Case, async: true

  alias NervesHub.Accounts.User.DisplayPreferences

  test "changeset/2 casts device_list_columns" do
    prefs = %DisplayPreferences{}
    changeset = DisplayPreferences.changeset(prefs, %{device_list_columns: [:health, :firmware]})
    assert changeset.valid?
    assert Ecto.Changeset.get_change(changeset, :device_list_columns) == [:health, :firmware]
  end

  test "changeset/2 with no attrs returns valid changeset" do
    prefs = %DisplayPreferences{}
    changeset = DisplayPreferences.changeset(prefs)
    assert changeset.valid?
  end

  test "device_list_columns/0 returns all columns" do
    columns = DisplayPreferences.device_list_columns()
    assert is_list(columns)
    assert :health in columns
  end

  test "deployment_group_list_columns/0 returns all columns" do
    columns = DisplayPreferences.deployment_group_list_columns()
    assert is_list(columns)
    assert :platform in columns
  end
end
