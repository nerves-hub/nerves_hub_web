defmodule Beamware.Certificate do
  require Record

  @spec get_common_name(binary) :: {:ok, binary} | :error
  def get_common_name(cert) do
    {_, cert, _, _} = :public_key.pkix_decode_cert(cert, :plain)
    [_, _, _ | cert] = Tuple.to_list(cert)
    cn = 
      Enum.filter(cert, &Record.is_record/1)
      |> Enum.reverse()
      |> Enum.reduce(nil, fn
          ({:rdnSequence, [attributes]}, nil) ->
            Enum.reduce(attributes, nil, fn
              ({:AttributeTypeAndValue, {2, 5, 4, 3}, cn}, nil) ->
                cn
              (_, cn) -> cn
            end)
          (_, cn) -> 
            cn
      end)
    case cn do
      cn when is_binary(cn) ->
        {:printableString, cn} = :public_key.der_decode(:"X520CommonName", cn)
        {:ok, to_string(cn)}
      _ -> :error
    end
  end

end
