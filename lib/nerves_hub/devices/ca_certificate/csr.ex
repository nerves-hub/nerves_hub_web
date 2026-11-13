defmodule NervesHub.Devices.CACertificate.CSR do
  alias NervesHub.Accounts.Org
  alias NervesHub.Certificate

  # could probably be a bit more specific
  @type csr :: tuple()
  @type cert :: tuple()

  @type csr_code() :: binary()

  @verification_token_context "ca_certificate"

  # ownership verification tokens are valid for 1 hour
  @verification_token_max_age 60 * 60

  @doc """
  Generates a code that should be used with `validate_csr`
  after a user creates the CSR.
  """
  @spec generate_code() :: csr_code()
  def generate_code() do
    :crypto.strong_rand_bytes(32) |> Base.encode16()
  end

  @doc """
  Checks the CSR's `common name` value. returns `:ok` if the value
  matches the `code` exactly. Returns `{:error, :invalid_csr}`
  otherwise.
  """
  @spec validate_csr(csr_code(), cert(), csr()) :: :ok | {:error, :invalid_csr}
  def validate_csr(code, cert, csr) do
    with ^code <- Certificate.get_common_name(csr),
         {:ok, _} <- :public_key.pkix_path_validation(cert, [csr], []) do
      :ok
    else
      _ -> {:error, :invalid_csr}
    end
  end

  def generate_verification_token(org) do
    NervesHubWeb.Endpoint
    |> Phoenix.Token.sign(@verification_token_context, "#{org.id}-#{org.name}", max_age: @verification_token_max_age)
  end

  def decrypt_verification_token(token) do
    NervesHubWeb.Endpoint
    |> Phoenix.Token.verify(@verification_token_context, token, max_age: @verification_token_max_age)
  end

  @typedoc """
  Why `validate_cert_ownership/3` refused a verification certificate.
  `ownership_error_message/1` explains each one.
  """
  @type ownership_error() ::
          :missing_verification_san
          | :invalid_verification_token
          | :expired_verification_token
          | :verification_token_for_another_org
          | :verification_cert_expired
          | :not_signed_by_ca

  @doc """
  Checks that whoever is registering the CA certificate `cert` for `org` holds
  its private key.

  `verification_cert` must be signed by `cert` and carry a verification token
  for `org` (from `generate_verification_token/1`) in its Subject Alternative
  Name, as `urn:nerveshub:verify:<token>`.

  `cert` may have expired. An expired CA can still sign, which is all this
  proves, and whether devices may register under it once it has expired is
  decided by its `check_expiration` setting when they connect (`NervesHub.SSL`).
  """
  @spec validate_cert_ownership(Org.t(), cert(), cert()) :: :ok | {:error, {:invalid_csr, ownership_error()}}
  def validate_cert_ownership(org, cert, verification_cert) do
    with {:ok, verification_token} <- verification_token(verification_cert),
         :ok <- check_verification_token(org, verification_token),
         :ok <- check_signed_by(verification_cert, cert) do
      :ok
    else
      {:error, reason} -> {:error, {:invalid_csr, reason}}
    end
  end

  @doc """
  A sentence explaining an `t:ownership_error/0` to whoever uploaded the
  verification certificate.
  """
  @spec ownership_error_message(ownership_error()) :: String.t()
  def ownership_error_message(:missing_verification_san) do
    "The verification certificate has no urn:nerveshub:verify: Subject Alternative Name. " <>
      "Put the registration code in the CSR's SAN, and keep it when signing (openssl's -copy_extensions copy)."
  end

  def ownership_error_message(:invalid_verification_token) do
    "The registration code in the verification certificate is not valid. Check it was copied in full."
  end

  def ownership_error_message(:expired_verification_token) do
    "The registration code in the verification certificate has expired. " <>
      "Codes are valid for one hour, so create a new verification certificate with a new code."
  end

  def ownership_error_message(:verification_token_for_another_org) do
    "The registration code in the verification certificate was issued for a different organization."
  end

  def ownership_error_message(:verification_cert_expired) do
    "The verification certificate has expired or is not yet valid."
  end

  def ownership_error_message(:not_signed_by_ca) do
    "The verification certificate was not signed by this CA certificate's private key."
  end

  defp verification_token(verification_cert) do
    case Certificate.get_san(verification_cert) do
      "urn:nerveshub:verify:" <> verification_token -> {:ok, verification_token}
      _ -> {:error, :missing_verification_san}
    end
  end

  defp check_verification_token(org, verification_token) do
    org_info = "#{org.id}-#{org.name}"

    case decrypt_verification_token(verification_token) do
      {:ok, ^org_info} -> :ok
      {:ok, _other_org} -> {:error, :verification_token_for_another_org}
      {:error, :expired} -> {:error, :expired_verification_token}
      {:error, _} -> {:error, :invalid_verification_token}
    end
  end

  defp check_signed_by(verification_cert, cert) do
    case :public_key.pkix_path_validation(cert, [verification_cert], verify_fun: {&verify_signed_by/3, cert}) do
      {:ok, _} -> :ok
      {:error, {:bad_cert, :cert_expired}} -> {:error, :verification_cert_expired}
      {:error, _} -> {:error, :not_signed_by_ca}
    end
  end

  # Path validation checks the CA's own validity as well as the verification
  # certificate's. Only the CA's is let through; see validate_cert_ownership/3.
  defp verify_signed_by(ca, {:bad_cert, :cert_expired}, ca), do: {:valid, ca}
  defp verify_signed_by(_cert, {:bad_cert, reason}, _ca), do: {:fail, reason}
  defp verify_signed_by(_cert, {:extension, _}, ca), do: {:unknown, ca}
  defp verify_signed_by(_cert, event, ca) when event in [:valid, :valid_peer], do: {:valid, ca}
end
