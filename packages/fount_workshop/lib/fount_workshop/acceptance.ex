defmodule FountWorkshop.Acceptance do
  @moduledoc "Explicit decisions against an exact stored candidate and authenticated approval authority."

  def accept(id, %Fount.Writing.Approval{} = approval, %Fount.Writing.Authority{} = authority, services),
    do:
      FountWorkshop.Store.call(services[:store], :accept_candidate, [
        id,
        [approval: approval, authority: authority]
      ])

  def accept(_id, _legacy_expected_revision, _legacy_review, _services),
    do: {:error, :authorized_approval_required}

  def reject(id, actor, services),
    do: FountWorkshop.Store.call(services[:store], :reject_candidate, [id, [actor: actor]])
end
