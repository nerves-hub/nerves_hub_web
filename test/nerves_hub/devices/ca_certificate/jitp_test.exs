defmodule NervesHub.Devices.CACertificate.JITPTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Devices.CACertificate.JITP

  test "changeset/2 with delete flag marks action as delete" do
    jitp = %JITP{}
    changeset = JITP.changeset(jitp, %{"delete" => "true"})
    assert changeset.action == :delete
  end

  test "changeset/2 with valid params" do
    jitp = %JITP{}

    changeset = JITP.changeset(jitp, %{"tags" => ["a", "b"], "description" => "desc", "product_id" => 1})
    assert changeset.valid?
  end
end
