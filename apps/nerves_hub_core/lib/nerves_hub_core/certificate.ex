defmodule NervesHubCore.Certificate do
  require Record

  @era 2000

  def get_authority_key_id(cert) do
    result =
      decode_cert(cert)
      |> List.last()
      |> Enum.find_value(fn
        {:Extension, {2, 5, 29, 35}, _, {:AuthorityKeyIdentifier, id, _, _}} -> id
        _ -> false
      end)

    if result do
      {:ok, result}
    else
      {:error, "Unable to parse certificate for authority_key_id"}
    end
  end

  @spec get_common_name(binary) :: {:ok, binary} | :error
  def get_common_name(cert) do
    cert = decode_cert(cert)
    [_, _, _ | cert] = cert

    cn =
      Enum.filter(cert, &Record.is_record/1)
      |> Enum.reverse()
      |> Enum.reduce(nil, fn
        {:rdnSequence, attributes}, nil ->
          List.flatten(attributes)
          |> Enum.reduce(nil, fn
            {:AttributeTypeAndValue, {2, 5, 4, 10}, cn}, nil ->
              cn

            _, cn ->
              cn
          end)

        _, cn ->
          cn
      end)

    case cn do
      {_, cn} when is_list(cn) ->
        {:ok, to_string(cn)}

      _res ->
        :error
    end
  end

  def get_serial_number(cert) do
    [_, _, serial | _cert] = decode_cert(cert)
    {:ok, to_string(serial)}
  end

  def get_validity(cert) do
    cert = decode_cert(cert)
    [_, _, _ | cert] = cert

    result =
      Enum.filter(cert, &Record.is_record/1)
      |> Enum.reverse()
      |> Enum.find(fn
        {:Validity, {:utcTime, _}, {:utcTime, _}} -> true
        _ -> false
      end)

    case result do
      {:Validity, {:utcTime, not_before}, {:utcTime, not_after}} ->
        not_before = to_string(not_before)
        not_after = to_string(not_after)
        {:ok, {convert_generalized_time(not_before), convert_generalized_time(not_after)}}

      _ ->
        {:error, "Unable to parse certificate for validity"}
    end
  end

  def binary_to_hex_string(binary) do
    binary
    |> Base.encode16()
    |> String.downcase()
  end

  defp decode_cert(<<"-----BEGIN CERTIFICATE-----", _rest::binary>> = cert) do
    [{_, cert, _}] = :public_key.pem_decode(cert)
    decode_cert(cert)
  end

  defp decode_cert(cert) do
    {_, cert, _, _} = :public_key.pkix_decode_cert(cert, :otp)
    Tuple.to_list(cert)
  end

  defp convert_generalized_time(timestamp) do
    <<year::binary-unit(8)-size(2), month::binary-unit(8)-size(2), day::binary-unit(8)-size(2),
      hour::binary-unit(8)-size(2), minute::binary-unit(8)-size(2),
      second::binary-unit(8)-size(2), "Z">> = timestamp

    NaiveDateTime.new(
      String.to_integer(year) + @era,
      String.to_integer(month),
      String.to_integer(day),
      String.to_integer(hour),
      String.to_integer(minute),
      String.to_integer(second)
    )
    |> case do
      {:ok, naive_date_time} ->
        DateTime.from_naive!(naive_date_time, "Etc/UTC")

      error ->
        error
    end
  end
end
