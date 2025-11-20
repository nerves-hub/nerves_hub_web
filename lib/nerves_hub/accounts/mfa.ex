defmodule NervesHub.Accounts.MFA do
  @moduledoc """
  The MFA context.
  """

  alias NervesHub.Accounts.MFA.UserTOTP
  alias NervesHub.Repo

  @doc """
  Gets the %UserTOTP{} entry, if any.
  """
  def get_user_totp(user) do
    Repo.get_by(UserTOTP, user_id: user.id)
  end

  @doc """
  Updates the TOTP secret.
  The secret is a random 20 bytes binary that is used to generate the QR Code to
  enable 2FA using auth applications. It will only be updated if the OTP code
  sent is valid.
  ## Examples
      iex> upsert_user_totp(%UserTOTP{secret: <<...>>}, code: "123456")
      {:ok, %Ecto.Changeset{data: %UserTOTP{}}}
  """
  def upsert_user_totp(totp, attrs) do
    Repo.transact(fn ->
      totp
      |> UserTOTP.upsert_changeset(attrs)
      |> Repo.insert(
        on_conflict: {:replace_all_except, [:id, :inserted_at]},
        conflict_target: [:user_id]
      )
    end)
    |> case do
      {:ok, totp} -> {:ok, totp}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Regenerates the user backup codes for totp.
  ## Examples
      iex> regenerate_user_totp_backup_codes(%UserTOTP{})
      {:ok, %UserTOTP{backup_codes: [...]}}
  """
  def regenerate_user_totp_backup_codes(totp) do
    totp
    |> Ecto.Changeset.change()
    |> UserTOTP.regenerate_backup_codes()
    |> Repo.update()
  end

  @doc """
  Disables the TOTP configuration for the given user.
  """
  def delete_user_totp(user_totp), do: Repo.delete(user_totp)

  @doc """
  Validates if the given TOTP code is valid.
  """
  def validate_user_totp(user, code) do
    totp = Repo.get_by!(UserTOTP, user_id: user.id)

    cond do
      UserTOTP.valid_totp?(totp, code) ->
        :valid_totp

      changeset = UserTOTP.validate_backup_code(totp, code) ->
        {:ok, totp} = Repo.update(changeset)
        {:valid_backup_code, Enum.count(totp.backup_codes, &is_nil(&1.used_at))}

      true ->
        :invalid
    end
  end

  @doc """
  Creates a changeset for the given TOTP struct.
  """
  def change_totp(totp) do
    UserTOTP.creation_changeset(totp, %{})
  end
end
