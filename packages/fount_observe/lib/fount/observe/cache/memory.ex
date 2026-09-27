defmodule Fount.Observe.Cache.Memory do
  @moduledoc "Process-owned, capacity-limited LRU measurement cache. No global table or durable store."
  use GenServer
  @behaviour Fount.Observe.Cache

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts)
  @impl Fount.Observe.Cache
  def get(server, key), do: GenServer.call(server, {:get, key})
  @impl Fount.Observe.Cache
  def put(server, key, results), do: GenServer.call(server, {:put, key, results})
  def size(server), do: GenServer.call(server, :size)
  def clear(server), do: GenServer.call(server, :clear)

  @impl GenServer
  def init(opts) do
    max_entries = Keyword.get(opts, :max_entries, 1_000)
    if is_integer(max_entries) and max_entries > 0,
      do: {:ok, %{entries: %{}, tick: 0, max: max_entries}},
      else: {:stop, :invalid_cache_capacity}
  end

  @impl GenServer
  def handle_call({:get, key}, _from, state) do
    case state.entries[key] do
      nil -> {:reply, :miss, state}
      {_, results} ->
        state = %{state | tick: state.tick + 1, entries: Map.put(state.entries, key, {state.tick + 1, results})}
        {:reply, {:hit, results}, state}
    end
  end
  def handle_call({:put, key, results}, _from, state) do
    entries = Map.put(state.entries, key, {state.tick + 1, results})
    entries = if map_size(entries) > state.max do
      {oldest, _} = Enum.min_by(entries, fn {_, {tick, _}} -> tick end)
      Map.delete(entries, oldest)
    else
      entries
    end
    {:reply, :ok, %{state | entries: entries, tick: state.tick + 1}}
  end
  def handle_call(:size, _from, state), do: {:reply, map_size(state.entries), state}
  def handle_call(:clear, _from, state), do: {:reply, :ok, %{state | entries: %{}}}
end
