defmodule FountWorkshop.Writing.ReviewGate do
  @moduledoc "The shared Core acceptance policy, also enforced under the database lock."
  defdelegate validate(candidate, review, approver), to: Fount.Writing.ReviewGate
end
