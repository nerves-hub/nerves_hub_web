defmodule NervesHub.Devices.CACertificate.JITPTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Devices.CACertificate.JITP
  alias NervesHub.Fixtures

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)

    %{user: user, org: org, product: product}
  end

  test "changeset/3 with delete flag marks action as delete", %{org: org} do
    changeset = JITP.changeset(%JITP{}, %{"delete" => "true"}, org.id)
    assert changeset.action == :delete
  end

  test "changeset/3 with valid params", %{org: org, product: product} do
    changeset =
      JITP.changeset(%JITP{}, %{"tags" => ["a", "b"], "description" => "desc", "product_id" => product.id}, org.id)

    assert changeset.valid?
  end

  test "changeset/3 needs only a product", %{org: org, product: product} do
    # What the form sends when the description and tags are left empty
    changeset = JITP.changeset(%JITP{}, %{"tags" => "", "description" => "", "product_id" => product.id}, org.id)
    assert changeset.valid?

    changeset = JITP.changeset(%JITP{}, %{"tags" => "prod", "description" => "desc"}, org.id)
    refute changeset.valid?
    assert errors_on(changeset) == %{product_id: ["can't be blank"]}
  end

  test "changeset/3 refuses a product from another org", %{org: org} do
    other_user = Fixtures.user_fixture()
    other_org = Fixtures.org_fixture(other_user)
    other_product = Fixtures.product_fixture(other_user, other_org)

    changeset =
      JITP.changeset(%JITP{}, %{"tags" => ["a"], "description" => "desc", "product_id" => other_product.id}, org.id)

    refute changeset.valid?
    assert %{product_id: ["must be a product in this organization"]} = errors_on(changeset)
  end
end
