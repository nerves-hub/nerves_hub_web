defmodule NervesHub.Webhooks.SignatureTest do
  use ExUnit.Case, async: true

  alias NervesHub.Webhooks.Signature

  # The vector the Standard Webhooks reference libraries test against. Matching
  # it is what lets a receiver verify deliveries with one of those libraries.
  @secret "whsec_MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw"
  @id "msg_p5jXN8AQM9LWM0D4loKWxJek"
  @timestamp 1_614_265_330
  @body ~s({"test": 2432232314})

  test "signs as the Standard Webhooks reference implementations do" do
    assert Signature.sign(@secret, @id, @timestamp, @body) == "v1,g0hM9SsE+OTPJTGt/tmIKtSyZlE3uFJELVlNIOLJ1OE="
  end

  test "generates secrets in the specification's format" do
    secret = Signature.generate_secret()

    assert "whsec_" <> encoded = secret
    assert byte_size(Base.decode64!(encoded)) == 32
    refute secret == Signature.generate_secret()
  end

  describe "verify/5" do
    test "accepts its own signature" do
      header = Signature.sign(@secret, @id, @timestamp, @body)

      assert Signature.verify(@secret, @id, @timestamp, @body, header)
    end

    test "accepts any one of several signatures, as during a secret rotation" do
      other = Signature.sign(Signature.generate_secret(), @id, @timestamp, @body)
      header = other <> " " <> Signature.sign(@secret, @id, @timestamp, @body)

      assert Signature.verify(@secret, @id, @timestamp, @body, header)
    end

    test "refuses a changed body, id or timestamp" do
      header = Signature.sign(@secret, @id, @timestamp, @body)

      refute Signature.verify(@secret, @id, @timestamp, @body <> " ", header)
      refute Signature.verify(@secret, "msg_other", @timestamp, @body, header)
      refute Signature.verify(@secret, @id, @timestamp + 1, @body, header)
    end

    test "refuses another secret's signature" do
      header = Signature.sign(Signature.generate_secret(), @id, @timestamp, @body)

      refute Signature.verify(@secret, @id, @timestamp, @body, header)
    end
  end
end
