defmodule NervesHubWebCore.Firmwares.Transfer.S3Ingress do
  @moduledoc """
  Parse server access logs and create firmware_transfer records

  https://docs.aws.amazon.com/AmazonS3/latest/dev/LogFormat.html
  """

  require Logger

  alias ExAws.S3
  alias NervesHubWebCore.Firmwares

  @regex ~r/(?P<bucket_owner>\S+) (?P<bucket>\S+) (?P<time>\[[^]]*\]) (?P<remote_ip>\S+) (?P<requester>\S+) (?P<request_id>\S+) (?P<operation>\S+) (?P<key>\S+) (?P<request>"[^"]*"|-) (?P<http_status>\S+) (?P<error_code>\S+) (?P<bytes_sent>\S+) (?P<object_size>\S+) (?P<total_time>\S+) (?P<turn_around_time>\S+) (?P<referrer>"[^"]*"|-) (?P<user_agent>"[^"]*"|-) (?P<version>\S)/

  def run() do
    bucket = Application.get_env(:nerves_hub_web_core, __MODULE__)[:bucket]

    S3.list_objects(bucket)
    |> ExAws.stream!()
    |> Enum.each(fn %{key: object_key} ->
      response =
        S3.get_object(bucket, object_key)
        |> ExAws.request()

      case response do
        {:ok, %{body: log}} ->
          errors =
            decode_log(log)
            |> List.flatten()
            |> Enum.reduce([], fn params, errors ->
              case Firmwares.create_firmware_transfer(params) do
                {:ok, _transfer} ->
                  errors

                {:error, error} ->
                  Logger.error(fn -> "Error inserting transfer: #{inspect(error)}" end)
                  [error | errors]
              end
            end)

          if errors == [] do
            S3.delete_object(bucket, object_key) |> ExAws.request()
          else
            Logger.error(fn -> "Error inserting transfers from object: #{inspect(object_key)}" end)
          end

        error ->
          Logger.error(fn ->
            "Error fetching object: #{inspect(object_key)}\n#{inspect(error)}"
          end)
      end
    end)
  end

  def decode_log(log) do
    String.split(log, "\n")
    |> Enum.reduce([], fn row, acc ->
      case decode_row(row) do
        {:ok, params} ->
          [params | acc]

        _ ->
          acc
      end
    end)
  end

  def decode_row(row) do
    row = String.trim(row)

    Regex.named_captures(@regex, row)
    |> decode_record
  end

  def decode_record(record) do
    bucket = NervesHubWebCore.Firmwares.Upload.S3.bucket()
    key = NervesHubWebCore.Firmwares.Upload.S3.key_prefix()
    key_size = byte_size(key)

    case record do
      %{
        "bucket" => ^bucket,
        "key" => <<^key::binary-size(key_size), _tail::binary>>,
        "operation" => "REST.GET.OBJECT"
      } = record ->
        {org_id, firmware_uuid} =
          Map.get(record, "key")
          |> decode_key()

        remote_ip = Map.get(record, "remote_ip")
        timestamp = Map.get(record, "time") |> decode_time()
        bytes_sent = Map.get(record, "bytes_sent") |> String.to_integer()
        bytes_total = Map.get(record, "object_size") |> String.to_integer()

        {:ok,
         %{
           org_id: org_id,
           firmware_uuid: firmware_uuid,
           remote_ip: remote_ip,
           bytes_sent: bytes_sent,
           bytes_total: bytes_total,
           timestamp: timestamp
         }}

      _ ->
        {:error, :invalid_transfer_record}
    end
  end

  def decode_time(time) do
    Timex.parse!(time, "[%d/%b/%Y:%H:%M:%S %z]", :strftime)
  end

  def decode_key(key) do
    path = String.split(key, "/")
    uuid = Enum.at(path, -1) |> Path.rootname()
    org_id = Enum.at(path, -2) |> parse_org_id()
    {org_id, uuid}
  end

  defp parse_org_id(nil), do: nil

  defp parse_org_id(org_id) when is_binary(org_id) do
    case Integer.parse(org_id) do
      :error -> nil
      {id, _} -> id
    end
  end
end
