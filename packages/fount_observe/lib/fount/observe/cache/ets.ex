defmodule Fount.Observe.Cache.ETS do
  @moduledoc """
  Process-owned, private ETS L1 cache with serialized LRU/TTL/quota accounting.
  Only immutable MeasurementResults belong here; Executor validates every hit.
  No global table, application environment, database, or screenplay revision key.
  """
  use GenServer
  @behaviour Fount.Observe.Cache

  def start_link(opts \\ []) do
    if is_list(opts) and Keyword.keyword?(opts) and
         Keyword.keys(opts) -- [:max_entries, :ttl_ms, :max_entry_bytes] == [] and
         positive?(Keyword.get(opts, :max_entries, 1000)) and
         positive?(Keyword.get(opts, :max_entry_bytes, 2_000_000)) and
         (Keyword.get(opts, :ttl_ms, 300_000) == :infinity or
            positive?(Keyword.get(opts, :ttl_ms, 300_000))) do
      GenServer.start_link(__MODULE__, opts)
    else
      {:error, :invalid_options}
    end
  end

  @impl true
  def get(cache, key), do: GenServer.call(cache, {:get, key})
  @impl true
  def put(cache, key, value), do: GenServer.call(cache, {:put, key, value})
  def size(cache), do: GenServer.call(cache, :size)
  def clear(cache), do: GenServer.call(cache, :clear)

  @impl true
  def init(opts) do
    {:ok,
     %{
       table: :ets.new(__MODULE__, [:set, :private]),
       tick: 0,
       max_entries: Keyword.get(opts, :max_entries, 1000),
       ttl_ms: Keyword.get(opts, :ttl_ms, 300_000),
       max_entry_bytes: Keyword.get(opts, :max_entry_bytes, 2_000_000)
     }}
  end

  @impl true
  def handle_call({:get, key}, _from, state) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(state.table, key) do
      [{^key, value, _tick, expiry}] when expiry == :infinity or expiry > now ->
        tick = state.tick + 1
        :ets.insert(state.table, {key, value, tick, expiry})
        {:reply, {:hit, value}, %{state | tick: tick}}

      _ ->
        :ets.delete(state.table, key)
        {:reply, :miss, state}
    end
  end

  def handle_call({:put, key, value}, _from, state) do
    purge(state)

    if byte_size(:erlang.term_to_binary(value)) <= state.max_entry_bytes do
      tick = state.tick + 1

      expiry =
        if state.ttl_ms == :infinity,
          do: :infinity,
          else: System.monotonic_time(:millisecond) + state.ttl_ms

      :ets.insert(state.table, {key, value, tick, expiry})
      evict(state)
      {:reply, :ok, %{state | tick: tick}}
    else
      {:reply, {:error, :entry_too_large}, state}
    end
  end

  def handle_call(:size, _from, state) do
    purge(state)
    {:reply, :ets.info(state.table, :size), state}
  end

  def handle_call(:clear, _from, state) do
    :ets.delete_all_objects(state.table)
    {:reply, :ok, state}
  end

  defp purge(state) do
    now = System.monotonic_time(:millisecond)

    :ets.select_delete(state.table, [
      {{:"$1", :"$2", :"$3", :"$4"}, [{:is_integer, :"$4"}, {:"=<", :"$4", now}], [true]}
    ])
  end

  defp evict(state) do
    if :ets.info(state.table, :size) > state.max_entries do
      {key, _value, _tick, _expiry} = :ets.foldl(&least_recent/2, nil, state.table)
      :ets.delete(state.table, key)
      evict(state)
    end
  end

  defp least_recent(row, nil), do: row
  defp least_recent(row, least) when elem(row, 2) < elem(least, 2), do: row
  defp least_recent(_row, least), do: least

  defp positive?(value), do: is_integer(value) and value > 0
end
