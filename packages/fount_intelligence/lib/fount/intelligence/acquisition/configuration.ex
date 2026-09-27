defmodule Fount.Intelligence.Acquisition.Configuration do
  @moduledoc "Explicit host construction of analytical services; no environment reads and no native SDK contract exposure."
  def provider(opts \\ []), do: Fount.Observe.provider(opts)
  def sandbox(fixtures, opts \\ []), do: Fount.Observe.Sandbox.new!(fixtures, opts)
end
