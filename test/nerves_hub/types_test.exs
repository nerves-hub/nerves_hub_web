defmodule NervesHub.TypesTest do
  use ExUnit.Case, async: true

  alias NervesHub.Accounts.User
  alias NervesHub.Types

  describe "resource" do
    test "type" do
      assert Types.Resource.type() == :string
    end

    test "cast" do
      # Valid cast
      assert Types.Resource.cast(User) == {:ok, User}
      assert Types.Resource.cast(to_string(User)) == {:ok, User}

      # Invalid cast
      assert Types.Resource.cast("AuditLog") == :error
      assert Types.Resource.cast(NervesHub) == :error
      assert Types.Resource.cast(:wat) == :error
      assert Types.Resource.cast(1234) == :error
    end

    test "dump" do
      # Valid dump
      assert Types.Resource.dump(User) == {:ok, to_string(User)}
      assert Types.Resource.dump(to_string(User)) == {:ok, to_string(User)}

      # Invalid dump
      assert Types.Resource.dump("AuditLog") == :error
      assert Types.Resource.dump(NervesHub) == :error
      assert Types.Resource.dump(:wat) == :error
      assert Types.Resource.dump(1234) == :error
    end

    test "load" do
      assert Types.Resource.load(to_string(User)) == {:ok, User}
    end
  end

  describe "known atoms" do
    setup do
      %{params: Types.KnownAtoms.init(values: [:health, :location])}
    end

    test "cast accepts known values as atoms or strings", %{params: params} do
      assert Types.KnownAtoms.cast(["health", :location], params) == {:ok, [:health, :location]}
      assert Types.KnownAtoms.cast(nil, params) == {:ok, nil}
    end

    test "cast rejects an unknown value", %{params: params} do
      assert Types.KnownAtoms.cast(["health", "weather"], params) == :error
      assert Types.KnownAtoms.cast(["health", nil], params) == :error
      assert Types.KnownAtoms.cast("health", params) == :error
    end

    test "load skips values it no longer knows", %{params: params} do
      assert Types.KnownAtoms.load(["health", "retired_box", "location"], nil, params) ==
               {:ok, [:health, :location]}

      assert Types.KnownAtoms.load(nil, nil, params) == {:ok, nil}
    end

    test "dump stores strings", %{params: params} do
      assert Types.KnownAtoms.dump([:health, :location], nil, params) == {:ok, ["health", "location"]}
      assert Types.KnownAtoms.dump([:weather], nil, params) == :error
    end
  end

  describe "KnownAtom" do
    setup do
      %{params: Types.KnownAtom.init(values: [:streets, :satellite])}
    end

    test "cast accepts a known value as an atom or a string", %{params: params} do
      assert Types.KnownAtom.cast("satellite", params) == {:ok, :satellite}
      assert Types.KnownAtom.cast(:streets, params) == {:ok, :streets}
      assert Types.KnownAtom.cast(nil, params) == {:ok, nil}
    end

    test "cast rejects an unknown value", %{params: params} do
      assert Types.KnownAtom.cast("watercolor", params) == :error
      assert Types.KnownAtom.cast(true, params) == :error
      assert Types.KnownAtom.cast(["streets"], params) == :error
    end

    test "load treats a value it no longer knows as nil", %{params: params} do
      assert Types.KnownAtom.load("satellite", nil, params) == {:ok, :satellite}
      assert Types.KnownAtom.load("watercolor", nil, params) == {:ok, nil}
      assert Types.KnownAtom.load(nil, nil, params) == {:ok, nil}
    end

    test "dump stores a string", %{params: params} do
      assert Types.KnownAtom.dump(:satellite, nil, params) == {:ok, "satellite"}
      assert Types.KnownAtom.dump(nil, nil, params) == {:ok, nil}
      assert Types.KnownAtom.dump(:watercolor, nil, params) == :error
    end
  end
end
