ExUnit.start()

defmodule Fount.TestApproval do
  @moduledoc false
  alias Fount.Writing.{Approval, Authority, Principal}

  def for_repo(repo, candidate_id, opts \\ []) do
    {:ok, candidate} = Fount.Persistence.candidate(repo, candidate_id)
    {:ok, principal} = Principal.new(Keyword.get(opts, :type, :human), Keyword.get(opts, :id, "writer"))
    {:ok, authority} = Authority.new(principal, candidate["screenplay_id"], [:approve])
    {:ok, approval} = Approval.direct(candidate, principal, Keyword.get(opts, :approval_id, Fount.ID.v4()), opts)
    {approval, authority}
  end
end
