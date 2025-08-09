defmodule NervesHub.MFA do
  @moduledoc """
  The MFA context.
  """

  import Ecto.Query, warn: false

  alias NervesHub.MFA.UserTOTP
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
    totp_changeset =
      totp
      |> UserTOTP.changeset(attrs)
      |> UserTOTP.ensure_backup_codes()
      # If we are updating, let's make sure the secret
      # in the struct propagates to the changeset.
      |> Ecto.Changeset.force_change(:secret, totp.secret)

    Ecto.Multi.new()
    |> Ecto.Multi.insert_or_update(:totp, totp_changeset)
    |> Repo.transaction()
    |> case do
      {:ok, %{totp: totp}} -> {:ok, totp}
      {:error, :totp, changeset, _} -> {:error, changeset}
    end
  end

  @doc """
  Regenerates the user backup codes for totp.
  ## Examples
      iex> regenerate_user_totp_backup_codes(%UserTOTP{})
      %UserTOTP{backup_codes: [...]}
  """
  def regenerate_user_totp_backup_codes(totp) do
    {:ok, updated_totp} =
      Repo.transaction(fn ->
        totp
        |> Ecto.Changeset.change()
        |> UserTOTP.regenerate_backup_codes()
        |> Repo.update!()
      end)

    updated_totp
  end

  @doc """
  Disables the TOTP configuration for the given user.
  """
  def delete_user_totp(user_totp) do
    Repo.delete!(user_totp)
    :ok
  end

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
    UserTOTP.changeset(totp, %{})
  end
end
