defmodule NervesHub.Accounts.User.DisplayPreferencesTest do
  use ExUnit.Case, async: true

  import NervesHub.DataCase, only: [errors_on: 1]

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

  describe "device details layout" do
    test "is the default until the user arranges the boxes" do
      assert DisplayPreferences.device_details_layout(%DisplayPreferences{}) ==
               {[:health, :alarms, :general_info, :deployment], [:location, :network_identities, :support_scripts]}

      refute DisplayPreferences.custom_device_details_layout?(%DisplayPreferences{})
    end

    test "is the user's arrangement once saved" do
      preferences = %DisplayPreferences{
        device_details_left: [:location, :general_info, :health, :alarms],
        device_details_right: [:support_scripts, :deployment, :network_identities]
      }

      assert DisplayPreferences.device_details_layout(preferences) ==
               {[:location, :general_info, :health, :alarms], [:support_scripts, :deployment, :network_identities]}

      assert DisplayPreferences.custom_device_details_layout?(preferences)
    end

    test "puts boxes missing from a saved layout at the bottom of their default column" do
      preferences = %DisplayPreferences{
        device_details_left: [:general_info, :health],
        device_details_right: [:location]
      }

      assert DisplayPreferences.device_details_layout(preferences) ==
               {[:general_info, :health, :alarms, :deployment], [:location, :network_identities, :support_scripts]}
    end

    test "changeset/2 rejects a box listed twice" do
      changeset =
        DisplayPreferences.changeset(%DisplayPreferences{}, %{
          device_details_left: ["health", "location"],
          device_details_right: ["location"]
        })

      refute changeset.valid?
      assert "lists a box more than once" in errors_on(changeset).device_details_left
    end

    test "changeset/2 rejects an unknown box" do
      changeset =
        DisplayPreferences.changeset(%DisplayPreferences{}, %{
          device_details_left: ["health", "weather"],
          device_details_right: []
        })

      refute changeset.valid?
    end
  end

  describe "map style" do
    test "is nil, following the theme, until the user picks one" do
      assert DisplayPreferences.map_style(nil) == nil
      assert DisplayPreferences.map_style(%DisplayPreferences{}) == nil
      assert DisplayPreferences.map_style(%DisplayPreferences{map_style: :satellite}) == :satellite
    end

    test "changeset/2 casts a known style" do
      changeset = DisplayPreferences.changeset(%DisplayPreferences{}, %{map_style: "outdoors"})

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :map_style) == :outdoors
    end

    test "changeset/2 treats an empty style as following the theme" do
      changeset = DisplayPreferences.changeset(%DisplayPreferences{map_style: :dark}, %{map_style: ""})

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :map_style) == nil
    end

    test "changeset/2 rejects an unknown style" do
      changeset = DisplayPreferences.changeset(%DisplayPreferences{}, %{map_style: "watercolor"})

      refute changeset.valid?
    end
  end
end
