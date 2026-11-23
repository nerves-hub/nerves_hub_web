defmodule NervesHub.AuditLogs.ProductAndOrgTemplatesTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.AuditLogs
  alias NervesHub.AuditLogs.OrgTemplates
  alias NervesHub.AuditLogs.ProductTemplates
  alias NervesHub.ErrorReports.ErrorGroup
  alias NervesHub.Fixtures
  alias NervesHub.Scripts.Script

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)

    %{user: user, org: org, product: product}
  end

  test "a product entry names the user and keeps what they typed as a value", %{user: user, product: product} do
    :ok = ProductTemplates.audit_script_deleted(user, product, %Script{name: "%{actor} <b>wipe</b>"})

    assert [log] = AuditLogs.logs_for(product)
    assert log.description == "#{user.name} removed script named %{actor} <b>wipe</b> from product #{product.name}"
    assert log.template == "%{actor} removed script named %{script} from product %{resource}"
    assert log.template_values["resource"] == %{"type" => "product", "id" => product.id, "name" => product.name}
  end

  test "an error's reason, which a device sent, is a value", %{user: user, product: product} do
    group = %ErrorGroup{id: 12, reason: "%{actor} badarg"}

    :ok = ProductTemplates.audit_error_group_muted(user, product, group)

    assert [log] = AuditLogs.logs_for(product)
    assert log.description == "#{user.name} muted error 12 (%{actor} badarg) for product #{product.name}"
    assert log.template_values["reason"] == "%{actor} badarg"
  end

  test "an org entry names the user and the org", %{user: user, org: org} do
    :ok = OrgTemplates.audit_two_factor_requirement(user, %{org | require_two_factor: true})

    assert [log] = AuditLogs.logs_for(org)
    assert log.description == "#{user.name} started requiring two-factor authentication of every member"
    assert log.template_values["resource"] == %{"type" => "org", "id" => org.id, "name" => org.name}
  end
end
