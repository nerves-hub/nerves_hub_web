defmodule NervesHubWebCore.Types do
  defmodule Tag do
    @behaviour Ecto.Type

    def type, do: {:array, :string}

    def cast(tags) when is_bitstring(tags) do
      tags
      |> String.split(",", trim: true)
      |> Stream.map(&String.trim/1)
      |> Enum.reject(&(byte_size(&1) == 0))
      |> cast()
    end

    def cast(tags) when is_list(tags) do
      if Enum.any?(tags, &(32 in to_charlist(&1))) do
        {:error, message: "tags cannot contain spaces"}
      else
        Ecto.Type.cast(type(), tags)
      end
    end

    def cast(_tag), do: :error

    def load(tags), do: Ecto.Type.load(type(), tags)
    def dump(tags), do: Ecto.Type.dump(type(), tags)
  end
end
