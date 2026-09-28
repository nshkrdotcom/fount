ExUnit.start()

defmodule FountWorkshop.TestApproval do
  @moduledoc false
  alias Fount.Writing.{Approval, Authority, Principal}
  alias FountWorkshop.Store

  def for_repo(repo, candidate_id, opts \\ []) do
    {:ok, candidate} = Fount.Persistence.candidate(repo, candidate_id)
    build(candidate, opts)
  end

  def for_services(services, candidate_id, opts \\ []) do
    {:ok, candidate} = Store.call(services[:store], :candidate, [candidate_id])
    build(candidate, opts)
  end

  defp build(candidate, opts) do
    type = Keyword.get(opts, :type, :human)
    principal_id = Keyword.get(opts, :id, "writer")
    {:ok, principal} = Principal.new(type, principal_id)
    {:ok, authority} = Authority.new(principal, candidate["screenplay_id"], [:approve])
    approval_id =
      Keyword.get(opts, :approval_id) ||
        Fount.ID.v5(candidate["screenplay_id"], ["test-approval:", candidate["id"], ":", to_string(type), ":", principal_id])
    {:ok, approval} = Approval.direct(candidate, principal, approval_id, opts)
    {approval, authority}
  end

  def accept(services, candidate_id, opts \\ []) do
    {approval, authority} = for_services(services, candidate_id, opts)
    FountWorkshop.Acceptance.accept(candidate_id, approval, authority, services)
  end

  def accept_repo(repo, candidate_id, opts \\ []) do
    {approval, authority} = for_repo(repo, candidate_id, opts)
    FountWorkshop.Review.accept(repo, candidate_id, approval, authority)
  end
end
