defmodule FountWorkshop.Acceptance do
  @moduledoc "Explicit writer decisions against the stored candidate, immutable review and current accepted head."
  def accept(id, expected_revision, review, services),
    do:
      FountWorkshop.Store.call(services[:store], :accept_candidate, [
        id,
        [expected_revision: expected_revision, actor: review["actor"], review: review]
      ])

  def reject(id, actor, services),
    do: FountWorkshop.Store.call(services[:store], :reject_candidate, [id, [actor: actor]])
end
