defmodule NervesHubWebCore.Devices.CACertificate.CSR do
  alias NervesHubWebCore.Certificate

  # could probably be a bit more specific
  @type csr :: tuple()
  @type cert :: tuple()

  @type csr_code() :: binary()

  @doc """
  Generates a code that should be used with `validate_csr`
  after a user creates the CSR.
  """
  @spec generate_code() :: csr_code()
  def generate_code do
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
end
