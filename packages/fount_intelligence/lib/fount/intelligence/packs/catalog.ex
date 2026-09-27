defmodule Fount.Intelligence.Packs.Catalog do
  @moduledoc "Explicit immutable catalog for validated genre packs. Installation and enablement are separate writer/studio decisions."

  alias Fount.Intelligence.Packs.GenrePack

  @enforce_keys [:packs]
  defstruct packs: %{}

  def new(core_assets \\ []) when is_list(core_assets) do
    Enum.reduce(core_assets, %__MODULE__{packs: %{}}, fn asset, catalog ->
      {:ok, value} = GenrePack.validate(asset)
      put(catalog, value, false)
    end)
  end

  def install(%__MODULE__{} = catalog, asset, opts \\ []) do
    with {:ok, value} <- GenrePack.validate(asset, opts),
         false <- Map.has_key?(catalog.packs, value["id"]) do
      {:ok, put(catalog, value, false)}
    else
      true -> {:error, :pack_already_installed}
      error -> error
    end
  end

  def enable(%__MODULE__{} = catalog, id), do: set_enabled(catalog, id, true)
  def disable(%__MODULE__{} = catalog, id), do: set_enabled(catalog, id, false)

  def fetch(%__MODULE__{} = catalog, id) do
    case catalog.packs[id] do
      nil -> {:error, :pack_not_installed}
      entry -> {:ok, Map.merge(entry["asset"], %{"enabled" => entry["enabled"]})}
    end
  end

  def enabled(%__MODULE__{} = catalog) do
    catalog.packs
    |> Map.values()
    |> Enum.filter(& &1["enabled"])
    |> Enum.map(& &1["asset"])
    |> Enum.sort_by(& &1["id"])
  end

  def list(%__MODULE__{} = catalog) do
    catalog.packs
    |> Enum.map(fn {_id, entry} -> Map.merge(entry["asset"], %{"enabled" => entry["enabled"]}) end)
    |> Enum.sort_by(& &1["id"])
  end

  defp set_enabled(%__MODULE__{} = catalog, id, enabled) do
    case catalog.packs[id] do
      nil -> {:error, :pack_not_installed}
      entry -> {:ok, %{catalog | packs: Map.put(catalog.packs, id, Map.put(entry, "enabled", enabled))}}
    end
  end

  defp put(catalog, asset, enabled),
    do: %{catalog | packs: Map.put(catalog.packs, asset["id"], %{"asset" => asset, "enabled" => enabled})}
end
