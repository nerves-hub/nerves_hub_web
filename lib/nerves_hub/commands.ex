defmodule NervesHub.Commands.Command do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Products.Product

  schema "commands" do
    belongs_to(:product, Product)

    field(:name, :string)
    field(:text, :string)

    timestamps()
  end

  def create_changeset(struct, params) do
    struct
    |> cast(params, [:name, :text])
    |> validate_required([:name, :text])
    |> validate_length(:name, lte: 255)
    |> validate_change(:text, fn :text, text ->
      if String.contains?(text, "\n") do
        [text: "cannot contain newlines"]
      else
        []
      end
    end)
  end

  def update_changeset(struct, params) do
    create_changeset(struct, params)
  end
end

defmodule NervesHub.Commands do
  import Ecto.Query

  alias NervesHub.Commands.Command
  alias NervesHub.Repo

  def all_by_product(product) do
    Command
    |> where([c], c.product_id == ^product.id)
    |> order_by(:name)
    |> Repo.all()
  end

  def get!(id) do
    Repo.get!(Command, id)
  end

  def get(product, id) do
    case Repo.get_by(Command, id: id, product_id: product.id) do
      nil ->
        {:error, :not_found}

      command ->
        {:ok, command}
    end
  end

  def create(product, params) do
    product
    |> Ecto.build_assoc(:commands)
    |> Command.create_changeset(params)
    |> Repo.insert()
  end

  def update(command, params) do
    command
    |> Command.update_changeset(params)
    |> Repo.update()
  end
end

defmodule NervesHub.Commands.Runner do
  use GenServer

  alias NervesHubWeb.Endpoint

  defmodule State do
    defstruct [:buffer, :clear?, :from, :receive_channel, :send_channel]
  end

  def send(device, command) do
    {:ok, pid} = start_link(device)
    GenServer.call(pid, {:send, command.text}, 10_000)
  end

  def start_link(device) do
    GenServer.start_link(__MODULE__, device.id)
  end

  def init(device_id) do
    state = %State{
      buffer: <<>>,
      clear?: true,
      from: nil,
      receive_channel: "user:console:#{device_id}",
      send_channel: "device:console:#{device_id}"
    }

    {:ok, state}
  end

  def handle_call({:send, text}, from, state) do
    text = ~s/IO.puts("[NERVESHUB:START]"); #{text}; IO.puts("[NERVESHUB:END]")/

    text
    |> String.graphemes()
    |> Enum.map(fn character ->
      Endpoint.broadcast_from!(self(), state.send_channel, "dn", %{"data" => character})
    end)

    Endpoint.subscribe(state.receive_channel)

    Endpoint.broadcast_from!(self(), state.send_channel, "dn", %{"data" => "\r"})

    {:noreply, %{state | from: from}}
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "up", payload: %{"data" => text}}, state) do
    state = %{state | buffer: state.buffer <> text}

    state =
      if state.clear? && String.contains?(state.buffer, ~s/[NERVESHUB:END]/) do
        %{state | buffer: <<>>, clear?: false}
      else
        state
      end

    if String.contains?(state.buffer, "[NERVESHUB:START]") &&
         String.contains?(state.buffer, "[NERVESHUB:END]") do
      buffer =
        state.buffer
        |> String.replace(~r/\A.+\[NERVESHUB:START\]\r\n/s, "")
        |> String.replace(~r/\[NERVESHUB:END].+\z/s, "")

      GenServer.reply(state.from, buffer)

      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end

  def handle_info(_, state), do: {:noreply, state}
end
