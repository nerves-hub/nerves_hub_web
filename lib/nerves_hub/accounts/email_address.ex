defmodule NervesHub.Accounts.EmailAddress do
  @moduledoc """
  Checks that an email address is one NervesHub can send mail to.

  The SMTP adapter hands every recipient to gen_smtp, which parses it as an
  RFC 5322 address and raises when it can't. Plenty of addresses that look
  fine at a glance fail that parse: consecutive dots (`a..b@example.com`), a
  dot at the start or end of the local part, a trailing dot on the domain.
  Checking with the same parser when an address is entered means an address
  that gets stored is one that can be emailed.
  """

  import Ecto.Changeset

  @doc """
  Returns true when `address` is one bare address that gen_smtp can parse.

  A display name (`Jane <jane@example.com>`), angle brackets or a list of
  addresses is not one bare address, so none of them pass.
  """
  @spec valid?(term()) :: boolean()
  def valid?(address) when is_binary(address) do
    with true <- String.valid?(address),
         {:ok, [{:undefined, parsed}]} <- :smtp_util.parse_rfc5322_addresses(address) do
      List.to_string(parsed) == address
    else
      _ -> false
    end
  end

  def valid?(_address), do: false

  @doc """
  Adds an error to `field` unless its change is an address `valid?/1` accepts.

  A field that already has an error is left alone, so a more specific message
  from an earlier validation isn't joined by this one.
  """
  @spec validate(Ecto.Changeset.t(), atom()) :: Ecto.Changeset.t()
  def validate(changeset, field) do
    if Keyword.has_key?(changeset.errors, field) do
      changeset
    else
      validate_change(changeset, field, fn ^field, address ->
        if valid?(address), do: [], else: [{field, "is not a valid email address"}]
      end)
    end
  end
end
