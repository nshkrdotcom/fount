defmodule FountWorkshop.Writing.ReviewGate do
  @moduledoc "The shared Core acceptance policy, also enforced under the database lock."
  defdelegate validate(candidate, review, expected_revision), to: Fount.Writing.ReviewGate
end
