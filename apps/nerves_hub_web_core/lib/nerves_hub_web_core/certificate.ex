defmodule NervesHubWebCore.Certificate do
  import X509.ASN1,
    only: [
      extension: 1,
      authority_key_identifier: 1,
      validity: 1,
      oid: 1,
      attribute_type_and_value: 1
    ]

  @era 2000

  defdelegate to_der(otp_certificate), to: X509.Certificate

  def get_aki(otp_certificate) do
    otp_certificate
    |> X509.Certificate.extensions()
    |> X509.Certificate.Extension.find(:authority_key_identifier)
    |> extension()
    |> Keyword.get(:extnValue)
    |> authority_key_identifier()
    |> Keyword.get(:keyIdentifier)
  end

  def get_ski(otp_certificate) do
    otp_certificate
    |> X509.Certificate.extensions()
    |> X509.Certificate.Extension.find(:subject_key_identifier)
    |> case do
      nil ->
        nil

      extension ->
        extension
        |> extension()
        |> Keyword.get(:extnValue)
    end
  end

  def get_common_name(otp_certificate) do
    {:rdnSequence, attributes} = X509.Certificate.subject(otp_certificate)

    common_name_oid = oid(:"id-at-commonName")

    attributes
    |> List.flatten()
    |> Enum.map(&attribute_type_and_value/1)
    |> Enum.find(&(&1[:type] == common_name_oid))
    |> case do
      nil ->
        nil

      common_name ->
        Keyword.get(common_name, :value)
        |> elem(1)
        |> to_string
    end
  end

  def get_serial_number(otp_certificate) do
    X509.Certificate.serial(otp_certificate)
    |> to_string
  end

  def get_validity(otp_certificate) do
    validity =
      X509.Certificate.validity(otp_certificate)
      |> validity()

    {type, not_before} = Keyword.get(validity, :notBefore)
    not_before = convert_timestamp({type, to_string(not_before)})

    {type, not_after} = Keyword.get(validity, :notAfter)
    not_after = convert_timestamp({type, to_string(not_after)})

    {not_before, not_after}
  end

  defp convert_timestamp({:utcTime, timestamp}) do
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

  defp convert_timestamp({:generalTime, timestamp}) do
    <<year::binary-unit(8)-size(4), month::binary-unit(8)-size(2), day::binary-unit(8)-size(2),
      hour::binary-unit(8)-size(2), minute::binary-unit(8)-size(2),
      second::binary-unit(8)-size(2), "Z">> = timestamp

    NaiveDateTime.new(
      String.to_integer(year),
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
