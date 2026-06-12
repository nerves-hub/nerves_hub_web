defmodule NervesHub.Devices.CACertificate.CSR do
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

  def validate_cert_ownership(org, cert, verification_cert) do
    with "urn:nerveshub:verify:" <> verification_token <- Certificate.get_san(verification_cert),
         {:ok, org_info} <- decrypt_verification_token(verification_token),
         true <- "#{org.id}-#{org.name}" == org_info,
         {:ok, _} <- :public_key.pkix_path_validation(cert, [verification_cert], []) do
      :ok
    else
      _ -> {:error, :invalid_csr}
    end
  end
end
