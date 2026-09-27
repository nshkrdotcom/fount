defmodule Fount.Intelligence.Reader.State do
  @moduledoc "Forward-only reader ledger at one presentation checkpoint."

  defstruct open_questions: %{},
            expectations: %{},
            promises: %{},
            threats: %{},
            reveals: %{},
            character_models: %{},
            suspense: %{},
            curiosity: %{},
            surprise: %{},
            comprehension_risks: %{},
            alignment: %{},
            relationships: %{},
            forward_pull: %{}

  @type t :: %__MODULE__{}
end
