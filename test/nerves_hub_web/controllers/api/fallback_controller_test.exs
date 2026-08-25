defmodule NervesHubWeb.API.FallbackControllerTest do
  use NervesHubWeb.ConnCase, async: true

  alias NervesHubWeb.API.FallbackController

  setup do
    conn =
      build_conn()
      |> put_req_header("accept", "application/json")
      |> Map.put(:params, %{"_format" => "json"})

    {:ok, conn: conn}
  end

  describe "call/2 {:error, :not_found}" do
    test "returns 404", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :not_found})
      assert conn.status == 404
    end
  end

  describe "call/2 {:error, :authentication_failed}" do
    test "returns 401", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :authentication_failed})
      assert conn.status == 401
    end
  end

  describe "call/2 {:error, :org_user_not_found}" do
    test "returns 422", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :org_user_not_found})
      assert conn.status == 422
    end
  end

  describe "call/2 {:error, :org_user_exists}" do
    test "returns 422", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :org_user_exists})
      assert conn.status == 422
    end
  end

  describe "call/2 {:error, binary}" do
    test "returns 500 for a string reason", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, "something went wrong"})
      assert conn.status == 500
    end
  end

  describe "call/2 {:error, atom}" do
    test "returns 500 for an unknown atom reason", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :some_unhandled_atom})
      assert conn.status == 500
    end
  end

  describe "call/2 :error" do
    test "returns 400", %{conn: conn} do
      conn = FallbackController.call(conn, :error)
      assert conn.status == 400
    end
  end

  describe "call/2 {:error, other}" do
    test "returns 500 for a non-binary, non-atom reason", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, %{some: "map"}})
      assert conn.status == 500
    end
  end

  describe "call/2 firmware upload errors" do
    test "returns 422 for :product_mismatch", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, {:product_mismatch, "declared", "expected"}})
      assert conn.status == 422
    end

    test "returns 422 for :update_tool_not_allowed", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, {:update_tool_not_allowed, "esp-idf", "my_product"}})
      assert conn.status == 422
    end

    test "returns 422 for :unsettable_product_params", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, {:unsettable_product_params, ["name", "org_id"]}})
      assert conn.status == 422
    end

    test "returns 422 for :firmware_not_signed", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :firmware_not_signed})
      assert conn.status == 422
    end

    test "returns 422 for :esp_idf_ecdsa_signatures_not_supported", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :esp_idf_ecdsa_signatures_not_supported})
      assert conn.status == 422
    end

    test "returns 422 for :unknown_signature_block_version", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :unknown_signature_block_version})
      assert conn.status == 422
    end

    test "returns 422 for :signature_block_corrupt", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :signature_block_corrupt})
      assert conn.status == 422
    end

    test "returns 422 for :unrecognised_firmware_format", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :unrecognised_firmware_format})
      assert conn.status == 422
    end

    test "returns 422 for {:invalid_version, raw}", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, {:invalid_version, "bad-ver"}})
      assert conn.status == 422
    end
  end

  describe "call/2 membership/identity errors" do
    test "returns 409 for :claimed_elsewhere", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :claimed_elsewhere})
      assert conn.status == 409
    end

    test "returns 422 for :invalid_member", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :invalid_member})
      assert conn.status == 422
    end

    test "returns 422 for :unknown_owner", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :unknown_owner})
      assert conn.status == 422
    end

    test "returns 422 for :unsupported_service", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :unsupported_service})
      assert conn.status == 422
    end

    test "returns 501 for :analytics_not_enabled", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :analytics_not_enabled})
      assert conn.status == 501
    end
  end

  describe "call/2 {:error, {key, message}} tuple" do
    test "returns 422 and renders the message", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, {:some_field, "something went wrong"}})
      assert conn.status == 422
    end
  end

  describe "call/2 {:error, %Ecto.Changeset{}}" do
    test "returns 422 for a non-conflict changeset error", %{conn: conn} do
      changeset = %Ecto.Changeset{
        valid?: false,
        errors: [{:name, {"can't be blank", [validation: :required]}}]
      }

      conn = FallbackController.call(conn, {:error, changeset})
      assert conn.status == 422
    end

    test "returns 409 conflict when the first error key is :firmwares", %{conn: conn} do
      changeset = %Ecto.Changeset{
        valid?: false,
        errors: [{:firmwares, {"has already been taken", []}}]
      }

      conn = FallbackController.call(conn, {:error, changeset})
      assert conn.status == 409
    end

    test "returns 409 conflict when the first error key is :deployment_groups", %{conn: conn} do
      changeset = %Ecto.Changeset{
        valid?: false,
        errors: [{:deployment_groups, {"has already been taken", []}}]
      }

      conn = FallbackController.call(conn, {:error, changeset})
      assert conn.status == 409
    end
  end
end
