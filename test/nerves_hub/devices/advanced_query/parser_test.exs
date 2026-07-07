defmodule NervesHub.Devices.AdvancedQuery.ParserTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Devices.AdvancedQuery.Parser

  setup {NervesHub.AdvancedQueryFixtures, :setup_devices}

  describe "parse/2" do
    test "parses a single comparison", %{product: product, platform: platform} do
      assert {:ok, {:comparison, "platform", "=", ^platform}} = Parser.parse(~s|platform = "#{platform}"|, product.id)
    end

    test "is case-insensitive for column names, operators, and keywords", %{product: product, platform: platform} do
      assert {:ok, ast} = Parser.parse(~s|PLATFORM = "#{platform}" AND tags CONTAINS "prod"|, product.id)

      assert ast ==
               {:and, {:comparison, "platform", "=", platform}, {:comparison, "tags", "contains", "prod"}}
    end

    test "parses and/or/not with correct precedence and grouping", %{product: product, platform: platform} do
      query = ~s|(platform = "#{platform}" and tags contains "prod") or not tags contains "beta"|

      assert {:ok, ast} = Parser.parse(query, product.id)

      assert ast ==
               {:or, {:and, {:comparison, "platform", "=", platform}, {:comparison, "tags", "contains", "prod"}},
                {:not, {:comparison, "tags", "contains", "beta"}}}
    end

    test "accepts unquoted bare-word values", %{product: product} do
      assert {:ok, {:comparison, "tags", "contains", "prod"}} = Parser.parse(~s|tags contains prod|, product.id)
    end

    test "parses a metric comparison with a numeric value", %{product: product} do
      assert {:ok, {:comparison, "metric:cpu_temp", ">", "10"}} = Parser.parse(~s|metric:cpu_temp > 10|, product.id)

      assert {:ok, {:comparison, "metric:load_15min", "<=", "1.5"}} =
               Parser.parse(~s|metric:load_15min <= 1.5|, product.id)
    end

    test "parses last_seen with a multi-word relative-time value", %{product: product} do
      assert {:ok, {:comparison, "last_seen", ">", "7 days ago"}} =
               Parser.parse(~s|last_seen > "7 days ago"|, product.id)

      assert {:ok, {:comparison, "last_seen", "<", "4 weeks ago"}} =
               Parser.parse(~s|last_seen < "4 weeks ago"|, product.id)

      assert {:error, message, _position} = Parser.parse(~s|last_seen > "1 day ago"|, product.id)
      assert message =~ "not a valid value"
    end

    test "parses the two-word `is not` operator (case-insensitively)", %{product: product} do
      assert {:ok, {:comparison, "update_status", "is", "updating"}} =
               Parser.parse(~s|update_status is "updating"|, product.id)

      assert {:ok, {:comparison, "update_status", "is not", "updating"}} =
               Parser.parse(~s|update_status is not "updating"|, product.id)

      assert {:ok, {:comparison, "update_status", "is not", "updating"}} =
               Parser.parse(~s|update_status IS NOT "updating"|, product.id)
    end

    test "does not confuse `is not`'s `not` with the NOT keyword", %{product: product} do
      assert {:ok,
              {:and, {:comparison, "update_status", "is not", "updating"}, {:comparison, "tags", "contains", "prod"}}} =
               Parser.parse(~s|update_status is not "updating" and tags contains "prod"|, product.id)
    end

    test "parses identifier `like`/`not like` with a freeform value", %{product: product} do
      assert {:ok, {:comparison, "identifier", "like", "%abc%"}} =
               Parser.parse(~s|identifier like "%abc%"|, product.id)

      assert {:ok, {:comparison, "identifier", "not like", "dev-_"}} =
               Parser.parse(~s|identifier not like "dev-_"|, product.id)
    end

    test "the leading `not` of `not like` is the operator, while `not <comparison>` is the keyword", %{
      product: product
    } do
      assert {:ok, {:comparison, "identifier", "not like", "%x%"}} =
               Parser.parse(~s|identifier not like "%x%"|, product.id)

      assert {:ok, {:not, {:comparison, "identifier", "like", "%x%"}}} =
               Parser.parse(~s|not identifier like "%x%"|, product.id)
    end

    test "rejects a non-numeric value for a metric column", %{product: product} do
      assert {:error, message, _position} = Parser.parse(~s|metric:cpu_temp > abc|, product.id)
      assert message =~ "not a valid value"
    end

    test "rejects a non-numeric operator for a metric column", %{product: product} do
      assert {:error, message, _position} = Parser.parse(~s|metric:cpu_temp contains "10"|, product.id)
      assert message =~ "not a valid operator"
    end

    test "rejects a metric column with an empty key", %{product: product} do
      assert {:error, message, _position} = Parser.parse(~s|metric: > 10|, product.id)
      assert message =~ "not a valid column"
    end

    test "rejects an unknown column", %{product: product} do
      assert {:error, message, 0} = Parser.parse(~s|bogus = "x"|, product.id)
      assert message =~ "not a valid column"
    end

    test "rejects an operator that isn't valid for the column", %{product: product} do
      assert {:error, message, _position} = Parser.parse(~s|tags = "prod"|, product.id)
      assert message =~ "not a valid operator"
    end

    test "rejects a value that isn't in the predefined set for the column", %{product: product} do
      assert {:error, message, _position} = Parser.parse(~s|platform = "doesnotexist"|, product.id)
      assert message =~ "not a valid value"
    end

    test "validates firmware against the product's firmware uuids", %{product: product, firmware: firmware} do
      assert {:ok, {:comparison, "firmware", "=", value}} = Parser.parse(~s|firmware = "#{firmware.uuid}"|, product.id)
      assert value == firmware.uuid

      assert {:error, message, _position} =
               Parser.parse(~s|firmware = "00000000-0000-0000-0000-000000000000"|, product.id)

      assert message =~ "not a valid value"
    end

    test "rejects unbalanced parentheses", %{product: product, platform: platform} do
      assert {:error, "expected closing parenthesis", _position} =
               Parser.parse(~s|(platform = "#{platform}"|, product.id)
    end

    test "rejects trailing input after a complete expression", %{product: product, platform: platform} do
      assert {:error, "unexpected trailing input", _position} =
               Parser.parse(~s|platform = "#{platform}" "#{platform}"|, product.id)
    end

    test "rejects an incomplete expression", %{product: product, platform: platform} do
      assert {:error, "expected a column name", _position} =
               Parser.parse(~s|platform = "#{platform}" and|, product.id)
    end
  end
end
