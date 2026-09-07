defmodule NervesHub.Accounts.UserTokenTest do
  use ExUnit.Case, async: true

  alias NervesHub.Accounts.UserToken
  alias NervesHub.Utils.Base62

  describe "verify_api_token_query/1 V1 token (nhu_ prefix)" do
    test "returns error tuple with :crc_mismatch when CRC does not match" do
      # Build a V1-format token: "nhu_" + 30-byte hmac + 6-byte crc_str
      # crc_str must be valid Base62 bytes but decode to a value that does not
      # match :erlang.crc32(hmac), so assert_crc returns :crc_mismatch
      hmac = :crypto.strong_rand_bytes(30)
      wrong_crc = rem(:erlang.crc32(hmac) + 1, 0xFFFFFFFF)
      # Encode wrong CRC as Base62 and take exactly 6 bytes
      crc_encoded = Base62.encode(<<wrong_crc::32>>)
      crc_str = crc_encoded |> String.pad_leading(6, "0") |> binary_part(0, 6)
      token = "nhu_" <> hmac <> crc_str

      assert {:error, :crc_mismatch} = UserToken.verify_api_token_query(token)
    end
  end
end
