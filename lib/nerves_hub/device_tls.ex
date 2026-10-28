defmodule NervesHub.DeviceTLS do
  @moduledoc """
  Checks a keypair for the device endpoint and puts it in front of new
  handshakes, without restarting the listener.

  Restarting is what this avoids: the listener holds every device connection
  on the node, so a restart to pick up a renewed certificate drops the whole
  fleet. It does not have to. The listener is configured with a path, and `:ssl`
  reads that file through its PEM cache on each new handshake. Replace the file
  and clear the cache, and the next handshake presents the new certificate
  while every established connection carries on with the one it negotiated.

  The key and chain live in one file, given to the listener as both `keyfile`
  and `certfile`: `:ssl` takes only the private key from the one and only the
  certificates from the other. Both are needed -- `:ssl` would read the key
  from `certfile` alone, but Bandit checks the options with `Plug.SSL`, which
  refuses to start without a `keyfile`. A single file is replaced with a
  single rename, so no handshake can ever read a new certificate alongside the
  old key.

  Everything installed here has been checked first. A keypair that does not
  match, a chain in the wrong order or a certificate for another host all
  produce a listener that accepts connections and fails every handshake, and
  unlike a bad deploy nothing restarts to undo it.
  """

  require Record

  @hrl "public_key/include/public_key.hrl"

  Record.defrecordp(
    :otp_certificate,
    :OTPCertificate,
    Record.extract(:OTPCertificate, from_lib: @hrl)
  )

  Record.defrecordp(
    :otp_tbs_certificate,
    :OTPTBSCertificate,
    Record.extract(:OTPTBSCertificate, from_lib: @hrl)
  )

  Record.defrecordp(
    :otp_subject_public_key_info,
    :OTPSubjectPublicKeyInfo,
    Record.extract(:OTPSubjectPublicKeyInfo, from_lib: @hrl)
  )

  @typedoc "Lowercase hex SHA-1 of the leaf's DER: its fingerprint."
  @type sha1 :: String.t()

  @typedoc "What `check/4` learned about a keypair it accepted."
  @type summary :: %{sha1: sha1(), subject: String.t(), not_after: DateTime.t()}

  @private_key_types [:RSAPrivateKey, :ECPrivateKey, :PrivateKeyInfo]

  @doc """
  Checks that `key_pem` and `chain_pem` would serve TLS for `host`.

  `host` may be `nil` to skip the name check, for a listener that is reached by
  address.
  """
  @spec check(String.t(), String.t(), String.t() | nil, DateTime.t()) ::
          {:ok, summary()} | {:error, String.t()}
  def check(key_pem, chain_pem, host, now \\ DateTime.utc_now()) do
    with {:ok, key} <- decode_key(key_pem),
         {:ok, [leaf | _] = chain} <- decode_chain(chain_pem),
         :ok <- check_key_matches(key, leaf),
         :ok <- check_chain_order(chain),
         {:ok, not_after} <- check_validity(leaf, now),
         :ok <- check_host(leaf, host) do
      {:ok, %{sha1: sha1(leaf), subject: subject(leaf), not_after: not_after}}
    end
  end

  @doc """
  Replaces `path` with the key and chain, then has `:ssl` read it afresh.

  The file is written beside `path` and renamed over it, so a handshake reads
  either the old keypair or the new one, never half of each. It is created
  readable by this user alone.
  """
  @spec install(Path.t(), String.t(), String.t()) :: :ok | {:error, File.posix()}
  def install(path, key_pem, chain_pem) do
    tmp = "#{path}.#{System.unique_integer([:positive])}.tmp"
    contents = [String.trim_trailing(key_pem), "\n", String.trim_trailing(chain_pem), "\n"]

    # Created empty and narrowed before the key is written, so it is never
    # readable by anyone else, even briefly.
    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(tmp, ""),
         :ok <- File.chmod(tmp, 0o600),
         :ok <- File.write(tmp, contents),
         :ok <- File.rename(tmp, path) do
      # Global, but harmless: anything else cached is simply read again.
      :ssl.clear_pem_cache()
    else
      error ->
        _ = File.rm(tmp)
        error
    end
  end

  @doc """
  The SHA-1 of the leaf in the file at `path`, or `nil` if there is none.
  """
  @spec installed_sha1(Path.t()) :: sha1() | nil
  def installed_sha1(path) do
    with {:ok, pem} <- File.read(path),
         {:ok, [leaf | _]} <- decode_chain(pem) do
      sha1(leaf)
    else
      _ -> nil
    end
  end

  defp decode_key(pem) do
    case Enum.filter(:public_key.pem_decode(pem), &(elem(&1, 0) in @private_key_types)) do
      [{_type, _der, :not_encrypted} = entry] ->
        {:ok, :public_key.pem_entry_decode(entry)}

      [{_type, _der, _cipher}] ->
        {:error, "the private key is encrypted"}

      [] ->
        {:error, "there is no private key"}

      _ ->
        {:error, "there is more than one private key"}
    end
  end

  defp decode_chain(pem) do
    case for({:Certificate, der, :not_encrypted} <- :public_key.pem_decode(pem), do: der) do
      [] -> {:error, "there are no certificates"}
      chain -> {:ok, chain}
    end
  end

  # Signs with the key and verifies with the certificate, which works the same
  # for every key type `:public_key` knows, rather than comparing fields that
  # differ between RSA and EC.
  defp check_key_matches(key, leaf) do
    probe = :crypto.strong_rand_bytes(32)

    if :public_key.verify(probe, :sha256, :public_key.sign(probe, :sha256, key), public_key(leaf)) do
      :ok
    else
      {:error, "the private key does not match the certificate"}
    end
  rescue
    _ -> {:error, "the private key does not match the certificate"}
  end

  defp public_key(der) do
    spki = der |> tbs() |> otp_tbs_certificate(:subjectPublicKeyInfo)
    {:PublicKeyAlgorithm, _algorithm, parameters} = otp_subject_public_key_info(spki, :algorithm)

    case otp_subject_public_key_info(spki, :subjectPublicKey) do
      {:ECPoint, _} = point -> {point, parameters}
      key -> key
    end
  end

  defp check_chain_order(chain) do
    chain
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.with_index(1)
    |> Enum.find_value(:ok, fn {[cert, issuer], position} ->
      if !:public_key.pkix_is_issuer(cert, issuer) do
        {:error, "the chain is out of order: certificate #{position} was not issued by certificate #{position + 1}"}
      end
    end)
  end

  defp check_validity(leaf, now) do
    {:Validity, not_before, not_after} = leaf |> tbs() |> otp_tbs_certificate(:validity)
    not_before = to_datetime(not_before)
    not_after = to_datetime(not_after)

    cond do
      DateTime.before?(now, not_before) ->
        {:error, "the certificate is not valid until #{not_before}"}

      DateTime.compare(now, not_after) != :lt ->
        {:error, "the certificate expired at #{not_after}"}

      true ->
        {:ok, not_after}
    end
  end

  defp check_host(_leaf, nil), do: :ok

  defp check_host(leaf, host) do
    # The :https match_fun is what accepts a wildcard; the default does not.
    if :public_key.pkix_verify_hostname(leaf, [dns_id: String.to_charlist(host)],
         match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
       ) do
      :ok
    else
      {:error, "the certificate does not cover #{host}"}
    end
  end

  defp tbs(der), do: der |> :public_key.pkix_decode_cert(:otp) |> otp_certificate(:tbsCertificate)

  defp subject(der) do
    {:rdnSequence, rdns} = der |> tbs() |> otp_tbs_certificate(:subject)

    rdns
    |> List.flatten()
    |> Enum.map_join(",", fn {:AttributeTypeAndValue, oid, value} ->
      "#{attribute_name(oid)}=#{attribute_value(value)}"
    end)
  end

  defp attribute_name({2, 5, 4, 3}), do: "CN"
  defp attribute_name({2, 5, 4, 6}), do: "C"
  defp attribute_name({2, 5, 4, 10}), do: "O"
  defp attribute_name({2, 5, 4, 11}), do: "OU"
  defp attribute_name(oid), do: oid |> Tuple.to_list() |> Enum.join(".")

  defp attribute_value({_string_type, value}) when is_binary(value), do: value
  defp attribute_value({_string_type, value}) when is_list(value), do: List.to_string(value)
  defp attribute_value(value) when is_binary(value), do: value
  defp attribute_value(value), do: inspect(value)

  defp sha1(der), do: :crypto.hash(:sha, der) |> Base.encode16(case: :lower)

  # X.509 has two time formats: UTCTime, two-digit years and only until 2049,
  # and GeneralizedTime, four-digit years, for everything from 2050 on.
  defp to_datetime({:utcTime, time}) do
    <<yy::binary-2, rest::binary>> = List.to_string(time)
    century = if String.to_integer(yy) >= 50, do: "19", else: "20"
    to_datetime({:generalTime, String.to_charlist(century <> yy <> rest)})
  end

  defp to_datetime({:generalTime, time}) do
    <<y::binary-4, mo::binary-2, d::binary-2, h::binary-2, mi::binary-2, s::binary-2, "Z">> =
      List.to_string(time)

    DateTime.from_iso8601("#{y}-#{mo}-#{d}T#{h}:#{mi}:#{s}Z") |> elem(1)
  end
end
