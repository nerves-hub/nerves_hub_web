defmodule NervesHubWWWWeb.OrgCertificateViewTest do
  use ExUnit.Case
  alias NervesHubWWWWeb.OrgCertificateView

  test "serial number is formatted in hex" do
    OrgCertificateView.format_serial("112346101875805641052401911002393715100") ==
      "54:85:12:79:FB:15:C2:FC:26:B2:50:35:4C:EF:A1:9C"
  end
end
