defmodule NervesHub.Certificate do
  require Record

  @spec get_device_serial(binary) :: {:ok, binary} | :error
  def get_device_serial(cert) do
    cert = decode_cert(cert)

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
      cn when is_binary(cn) ->
        {:printableString, cn} = :public_key.der_decode(:X520CommonName, cn)
        {:ok, to_string(cn)}

      _ ->
        :error
    end
  end

  defp decode_cert(<<"-----BEGIN CERTIFICATE-----", _rest::binary>> = cert) do
    [{_, cert, _}] = :public_key.pem_decode(cert)
    decode_cert(cert)
  end

  defp decode_cert(cert) do
    {_, cert, _, _} = :public_key.pkix_decode_cert(cert, :plain)
    [_, _, _ | cert] = Tuple.to_list(cert)
    cert
  end
end
