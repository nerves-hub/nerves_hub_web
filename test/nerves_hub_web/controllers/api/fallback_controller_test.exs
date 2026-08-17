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
