defmodule NervesHub.Accounts.TwoFactor do
  @moduledoc """
  Two-factor authentication: a code from an authenticator app, asked for
  after the password (or Google) when someone signs in.

  It's optional for each user. An organization can require it of its
  members (`Org.require_two_factor`), and a member without it can't reach
  that organization, through the web UI, the API, consoles or Slack, until
  they turn it on. Their account and other organizations work as before.

  Codes are TOTP (RFC 6238) with the usual 30 second period and six digits,
  which every authenticator app reads from the `otpauth://` URI a QR code
  carries. A code from the period before or after the current one is
  accepted too, for clocks that drift. Each period's code works once.

  Setting it up also gives the user ten recovery codes, each good for one
  sign-in without the app. Only their hashes are kept.

  Checking a code that is wrong can be tried without end by whoever is asking,
  so every caller limits the tries first: `NervesHubWeb.Plugs.Attack` has a
  limit for signing in and another for the account's two-factor page.

  The TOTP secret is encrypted with `NervesHub.Types.Encrypted`, so this is
  only offered when that has a key (`available?/0`).
  """

  import Ecto.Query

  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Accounts.PubSub, as: AccessPubSub
  alias NervesHub.Accounts.User
  alias NervesHub.Accounts.UserNotifier
  alias NervesHub.Accounts.UserTOTP
  alias NervesHub.AuditLogs.OrgTemplates
  alias NervesHub.Branding
  alias NervesHub.Repo
  alias NervesHub.Types.Encrypted

  require Logger

  @period 30
  @recovery_code_count 10
  @recovery_code_alphabet ~c"abcdefghijklmnopqrstuvwxyz234567"

  @type verify_result ::
          {:ok, :totp}
          | {:ok, {:recovery_code, non_neg_integer()}}
          | {:error, :invalid_code | :secret_unreadable}

  @doc """
  Whether this instance can store TOTP secrets. Without a
  `SECRETS_ENCRYPTION_KEY` nobody can turn two-factor on, and no
  organization can require it.
  """
  @spec available?() :: boolean()
  def available?(), do: Encrypted.configured?()

  @doc """
  Whether the user has two-factor authentication on.
  """
  @spec enabled?(User.t()) :: boolean()
  def enabled?(%User{id: user_id}) do
    UserTOTP
    |> where(user_id: ^user_id)
    |> Repo.exists?()
  end

  @doc """
  The user's authenticator app, if they have set one up, without its secret:
  nothing but checking a code needs that, and it can't be decrypted once
  `SECRETS_ENCRYPTION_KEY` has changed, which shouldn't stop the account's
  two-factor page from loading.
  """
  @spec get(User.t()) :: UserTOTP.t() | nil
  def get(%User{id: user_id}) do
    UserTOTP
    |> where(user_id: ^user_id)
    |> select([t], struct(t, [:id, :user_id, :last_used_at, :recovery_codes, :inserted_at, :updated_at]))
    |> Repo.one()
  end

  @doc """
  A new random secret, for a user to add to their authenticator app. Nothing
  is stored until `enable/3` confirms the app has it.
  """
  @spec new_secret() :: binary()
  def new_secret(), do: NimbleTOTP.secret()

  @doc """
  The `otpauth://` URI an authenticator app reads, from a QR code, to add
  `secret`. Labelled with the instance's name and the user's email, which is
  how the app lists it.
  """
  @spec otpauth_uri(User.t(), binary()) :: String.t()
  def otpauth_uri(%User{email: email}, secret) do
    issuer = Branding.friendly_platform_name()
    NimbleTOTP.otpauth_uri("#{issuer}:#{email}", secret, issuer: issuer)
  end

  @doc """
  `secret` as people type it into an authenticator app that can't scan the
  QR code: base32, in groups of four.
  """
  @spec format_secret(binary()) :: String.t()
  def format_secret(secret) do
    secret
    |> Base.encode32(padding: false)
    |> String.graphemes()
    |> Enum.chunk_every(4)
    |> Enum.map_join(" ", &Enum.join/1)
  end

  @doc """
  Turns two-factor on with `secret`, once `code` shows the user's app has
  it. Returns the recovery codes, which are shown once and never again.

  Browser sessions the user already has stay signed in, though none of them
  typed a code. The account's two-factor page signs the others out with
  `NervesHub.Accounts.delete_other_user_session_tokens/2`, once this returns.

  The user is emailed that it was turned on.
  """
  @spec enable(User.t(), binary(), String.t()) ::
          {:ok, [String.t()]} | {:error, :invalid_code | :already_enabled | :unavailable}
  def enable(%User{} = user, secret, code) when is_binary(secret) do
    with {:available, true} <- {:available, available?()},
         {:ok, period_start} <- match_totp(secret, normalize(code)) do
      insert_totp(user, secret, period_start)
    else
      {:available, false} -> {:error, :unavailable}
      :error -> {:error, :invalid_code}
    end
  end

  defp insert_totp(user, secret, period_start) do
    {codes, hashes} = new_recovery_codes(user)

    Repo.transact(fn ->
      %UserTOTP{user_id: user.id}
      |> Ecto.Changeset.change(secret: secret, last_used_at: period_start, recovery_codes: hashes)
      |> Ecto.Changeset.unique_constraint(:user_id)
      |> Repo.insert()
      |> case do
        {:ok, _totp} ->
          {:ok, _job} = UserNotifier.deliver_two_factor_enabled(user)
          {:ok, codes}

        {:error, _changeset} ->
          {:error, :already_enabled}
      end
    end)
  end

  @doc """
  Checks a code someone signing in as `user` typed: six digits from their
  app, or one of their recovery codes, which is used up. Spaces and dashes
  are ignored.

  A user without two-factor has no code that works. A code from the app
  can't be checked once `SECRETS_ENCRYPTION_KEY` has changed
  (`:secret_unreadable`), but recovery codes, which don't need the secret,
  still work, so the user can sign in and set their app up again.
  """
  @spec verify(User.t(), String.t()) :: verify_result()
  def verify(%User{} = user, code) when is_binary(code) do
    case get(user) do
      %UserTOTP{} = totp -> verify_code(totp, normalize(code))
      nil -> {:error, :invalid_code}
    end
  end

  def verify(%User{}, _code), do: {:error, :invalid_code}

  @doc """
  Checks a code as `verify/2` does, but leaves a recovery code unused, for
  something that can still fail after the code is checked, such as confirming
  with Google, which needs a trip to Google first. A recovery code comes back
  as `{:ok, {:held_recovery_code, held}}`: pass `held` to
  `use_held_recovery_code/2` once the rest has gone through. A code from the
  app is used up as `verify/2` uses it, since the app shows a new one every 30
  seconds.

  `held` is the code's hash, which can't be turned back into the code (see
  `hash_recovery_code/2`), so it may be kept in the session.
  """
  @spec verify_and_hold(User.t(), String.t()) ::
          {:ok, :totp}
          | {:ok, {:held_recovery_code, binary()}}
          | {:error, :invalid_code | :secret_unreadable}
  def verify_and_hold(%User{id: user_id} = user, code) when is_binary(code) do
    code = normalize(code)

    case get(user) do
      %UserTOTP{} = totp ->
        hash = hash_recovery_code(user_id, code)

        cond do
          String.match?(code, ~r/\A\d{6}\z/) -> verify_totp(totp, code)
          hash in totp.recovery_codes -> {:ok, {:held_recovery_code, hash}}
          true -> {:error, :invalid_code}
        end

      nil ->
        {:error, :invalid_code}
    end
  end

  def verify_and_hold(%User{}, _code), do: {:error, :invalid_code}

  @doc """
  Uses up a recovery code `verify_and_hold/2` held. Refused with
  `:invalid_code` when it has been used since, or two-factor turned off or
  given new codes.
  """
  @spec use_held_recovery_code(User.t(), binary()) ::
          {:ok, {:recovery_code, non_neg_integer()}} | {:error, :invalid_code}
  def use_held_recovery_code(%User{} = user, held) when is_binary(held) do
    case get(user) do
      %UserTOTP{} = totp -> remove_recovery_code(totp, held)
      nil -> {:error, :invalid_code}
    end
  end

  @doc """
  Turns two-factor off, given a current code or a recovery code, which
  proves whoever asks still holds the second factor rather than only a
  signed in browser.

  Whatever the user has open in an organization that requires two-factor is
  told, so those pages and consoles close.

  The user is emailed that it was turned off.
  """
  @spec disable(User.t(), String.t()) :: :ok | {:error, :invalid_code | :secret_unreadable}
  def disable(%User{} = user, code) do
    with {:ok, _how} <- verify(user, code),
         {:ok, :ok} <- Repo.transact(fn -> delete_and_notify(user) end) do
      user
      |> orgs_requiring()
      |> Enum.each(fn org -> _ = AccessPubSub.broadcast_membership_changed(org.id, user.id) end)

      :ok
    end
  end

  defp delete_and_notify(user) do
    UserTOTP
    |> where(user_id: ^user.id)
    |> Repo.delete_all()
    |> case do
      {0, _} ->
        # Turned off by another request in the meantime, which sent the email.
        {:ok, :ok}

      {1, _} ->
        {:ok, _job} = UserNotifier.deliver_two_factor_disabled(user)
        {:ok, :ok}
    end
  end

  @doc """
  Replaces the user's recovery codes with ten new ones, given a current code
  or a recovery code. The old codes stop working, and the user is emailed
  that they were replaced.
  """
  @spec regenerate_recovery_codes(User.t(), String.t()) ::
          {:ok, [String.t()]} | {:error, :invalid_code | :secret_unreadable}
  def regenerate_recovery_codes(%User{} = user, code) do
    with {:ok, _how} <- verify(user, code) do
      {codes, hashes} = new_recovery_codes(user)

      Repo.transact(fn ->
        UserTOTP
        |> where(user_id: ^user.id)
        |> Repo.update_all(set: [recovery_codes: hashes])
        |> case do
          {1, _} ->
            {:ok, _job} = UserNotifier.deliver_two_factor_recovery_codes(user)
            {:ok, codes}

          {0, _} ->
            # Turned off by another request since the code was checked, so
            # there is nothing for the code to have been for.
            {:error, :invalid_code}
        end
      end)
    end
  end

  @doc """
  Whether `user` may reach `org`: the org doesn't require two-factor, or
  the user has it on. Takes the org, or its id when only that is to hand.
  """
  @spec meets_org_requirement?(Org.t() | pos_integer(), User.t()) :: boolean()
  def meets_org_requirement?(%Org{require_two_factor: false}, %User{}), do: true
  def meets_org_requirement?(%Org{require_two_factor: true}, %User{} = user), do: enabled?(user)

  def meets_org_requirement?(org_id, %User{} = user) when is_integer(org_id) do
    required? =
      Org
      |> where(id: ^org_id)
      |> select([o], o.require_two_factor)
      |> Repo.one()

    required? != true or enabled?(user)
  end

  @doc """
  The orgs `user` is a member of that require two-factor, by name.
  """
  @spec orgs_requiring(User.t()) :: [Org.t()]
  def orgs_requiring(%User{id: user_id}) do
    Org
    |> join(:inner, [o], ou in OrgUser, on: ou.org_id == o.id and ou.user_id == ^user_id and is_nil(ou.deleted_at))
    |> where([o], o.require_two_factor and is_nil(o.deleted_at))
    |> order_by([o], o.name)
    |> Repo.all()
  end

  @doc """
  The org's members who don't have two-factor on, by name.
  """
  @spec members_without(Org.t()) :: [User.t()]
  def members_without(%Org{id: org_id}) do
    User
    |> join(:inner, [u], ou in OrgUser, on: ou.user_id == u.id and ou.org_id == ^org_id and is_nil(ou.deleted_at))
    |> join(:left, [u], t in UserTOTP, on: t.user_id == u.id)
    |> where([u, _ou, t], is_nil(t.id) and is_nil(u.deleted_at))
    |> order_by([u], u.name)
    |> Repo.all()
  end

  @doc """
  Turns the org's two-factor requirement on or off, for `admin`, whose
  permission to change the org's settings the caller has checked.

  Only someone with two-factor on can turn the requirement on, so an admin
  can't lock themselves out of the org by turning it on.

  A change is recorded in the org's audit log; saving the same value again
  isn't. Turning it on emails every other member, asking those without it to
  set it up, and tells whatever those without it have open in the org, so
  their pages and consoles close rather than staying open until they next
  navigate.
  """
  @spec set_org_requirement(Org.t(), User.t(), boolean()) ::
          {:ok, Org.t()} | {:error, :two_factor_off | :unavailable | Ecto.Changeset.t()}
  def set_org_requirement(%Org{} = org, %User{} = admin, required) when is_boolean(required) do
    cond do
      required and not available?() -> {:error, :unavailable}
      required and not enabled?(admin) -> {:error, :two_factor_off}
      true -> update_org_requirement(org, admin, required)
    end
  end

  defp update_org_requirement(org, admin, required) do
    changeset = Org.require_two_factor_changeset(org, required)

    result =
      Repo.transact(fn ->
        with {:ok, updated} <- Repo.update(changeset),
             :ok <- record_change(changeset, updated, admin) do
          {:ok, updated}
        end
      end)

    # Once committed, as each subscriber reads the requirement straight away.
    case result do
      {:ok, %Org{require_two_factor: true} = updated} ->
        updated
        |> members_without()
        |> Enum.each(fn member -> _ = AccessPubSub.broadcast_membership_changed(updated.id, member.id) end)

      _ ->
        :ok
    end

    result
  end

  defp record_change(changeset, org, admin) do
    if Ecto.Changeset.changed?(changeset, :require_two_factor) do
      :ok = OrgTemplates.audit_two_factor_requirement(admin, org)
      notify_members(org, admin)
    else
      :ok
    end
  end

  defp notify_members(%Org{require_two_factor: true} = org, admin) do
    _jobs = UserNotifier.deliver_all_org_requires_two_factor(org, admin, members_with_two_factor(org))
    :ok
  end

  defp notify_members(%Org{require_two_factor: false}, _admin), do: :ok

  # Each member, with whether they have two-factor on.
  defp members_with_two_factor(%Org{id: org_id}) do
    User
    |> join(:inner, [u], ou in OrgUser, on: ou.user_id == u.id and ou.org_id == ^org_id and is_nil(ou.deleted_at))
    |> join(:left, [u], t in UserTOTP, on: t.user_id == u.id)
    |> where([u], is_nil(u.deleted_at))
    |> select([u, _ou, t], {u, not is_nil(t.id)})
    |> Repo.all()
  end

  # A TOTP code is six digits; anything else is tried as a recovery code.
  defp verify_code(totp, code) do
    if String.match?(code, ~r/\A\d{6}\z/) do
      verify_totp(totp, code)
    else
      verify_recovery_code(totp, code)
    end
  end

  defp verify_totp(%UserTOTP{} = totp, code) do
    with {:ok, secret} <- load_secret(totp),
         {:ok, period_start} <- match_totp(secret, code),
         true <- claim_period(totp, period_start) do
      {:ok, :totp}
    else
      {:error, :secret_unreadable} -> {:error, :secret_unreadable}
      _ -> {:error, :invalid_code}
    end
  end

  # Read as the stored bytes and decrypted here, rather than by loading the
  # field, which raises when the key has changed since it was stored.
  defp load_secret(%UserTOTP{id: id, user_id: user_id}) do
    stored =
      UserTOTP
      |> where(id: ^id)
      |> select([t], type(t.secret, :binary))
      |> Repo.one()

    with <<_::binary>> <- stored,
         true <- available?() || :error,
         {:ok, secret} <- Encrypted.load(stored) do
      {:ok, secret}
    else
      nil ->
        # Turned off since the row was read.
        {:error, :invalid_code}

      :error ->
        Logger.error(
          "[TwoFactor] The TOTP secret of user #{user_id} can't be decrypted. Has SECRETS_ENCRYPTION_KEY changed?"
        )

        {:error, :secret_unreadable}
    end
  end

  # The start of the period whose code `code` is: this one, the one before or
  # the one after.
  defp match_totp(secret, code) do
    now = System.os_time(:second)

    Enum.find_value([now, now - @period, now + @period], :error, fn time ->
      if NimbleTOTP.valid?(secret, code, time: time) do
        {:ok, DateTime.from_unix!(time - rem(time, @period))}
      end
    end)
  end

  # Records the period as used, unless it or a later one already was. Done in
  # the update's condition, so two requests with the same code can't both
  # have it accepted.
  defp claim_period(%UserTOTP{id: id}, period_start) do
    {count, _} =
      UserTOTP
      |> where(id: ^id)
      |> where([t], is_nil(t.last_used_at) or t.last_used_at < ^period_start)
      |> Repo.update_all(set: [last_used_at: period_start])

    count == 1
  end

  defp verify_recovery_code(%UserTOTP{user_id: user_id} = totp, code) do
    remove_recovery_code(totp, hash_recovery_code(user_id, code))
  end

  defp remove_recovery_code(%UserTOTP{id: id}, hash) do
    # Removed in the same statement that finds it, so a code can only be used
    # once even by two requests at the same time.
    UserTOTP
    |> where(id: ^id)
    |> where([t], fragment("? = ANY(?)", ^hash, t.recovery_codes))
    |> select([t], t.recovery_codes)
    |> update([t], set: [recovery_codes: fragment("array_remove(?, ?)", t.recovery_codes, ^hash)])
    |> Repo.update_all([])
    |> case do
      {1, [remaining]} -> {:ok, {:recovery_code, length(remaining)}}
      {0, _} -> {:error, :invalid_code}
    end
  end

  defp new_recovery_codes(%User{id: user_id}) do
    codes = for _ <- 1..@recovery_code_count, do: random_recovery_code()
    hashes = Enum.map(codes, &hash_recovery_code(user_id, normalize(&1)))

    {codes, hashes}
  end

  # Sixteen characters of base32, 80 bits, shown as four groups of four.
  defp random_recovery_code() do
    chars = for <<byte <- :crypto.strong_rand_bytes(16)>>, do: Enum.at(@recovery_code_alphabet, rem(byte, 32))

    chars
    |> Enum.chunk_every(4)
    |> Enum.join("-")
  end

  # Codes are random and 80 bits, too many to search for from a leaked hash,
  # so a fast hash is enough; the user id keeps the same code from hashing
  # alike for two users.
  defp hash_recovery_code(user_id, code), do: :crypto.hash(:sha256, "#{user_id}:#{code}")

  defp normalize(code) when is_binary(code) do
    code
    |> String.replace(~r/[\s-]/, "")
    |> String.downcase()
  end

  defp normalize(_code), do: ""
end
