defmodule NervesHubWWWWeb.OrgCertificateViewTest do
  use ExUnit.Case
  alias NervesHubWWWWeb.OrgCertificateView

  test "serial number is formatted in hex" do
    OrgCertificateView.format_serial(112_346_101_875_805_641_052_401_911_002_393_715_100) ==
      "54:85:12:79:FB:15:C2:FC:26:B2:50:35:4C:EF:A1:9C"
  end
end
