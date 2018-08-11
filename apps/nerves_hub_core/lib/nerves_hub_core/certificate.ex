defmodule NervesHubCore.Certificate do
  require Record

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

  defp decode_cert(<<"-----BEGIN CERTIFICATE-----", _rest::binary>> = cert) do
    [{_, cert, _}] = :public_key.pem_decode(cert)
    decode_cert(cert)
  end

  defp decode_cert(cert) do
    {_, cert, _, _} = :public_key.pkix_decode_cert(cert, :otp)
    Tuple.to_list(cert)
  end
end
