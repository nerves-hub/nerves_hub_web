defmodule NervesHubWeb.Components.UtilsTest do
  use ExUnit.Case

  alias NervesHubWeb.Components.Utils

  describe "format_serial/1" do
    test "serial number is formatted in hex" do
      assert Utils.format_serial("112346101875805641052401911002393715100") ==
               "54:85:12:79:FB:15:C2:FC:26:B2:50:35:4C:EF:A1:9C"
    end
  end

  describe "role_options/0" do
    test "a list of formatted tuples is returned" do
      assert Utils.role_options() == [
               {"Admin", :admin},
               {"Manage", :manage},
               {"View", :view}
             ]
    end
  end
end
