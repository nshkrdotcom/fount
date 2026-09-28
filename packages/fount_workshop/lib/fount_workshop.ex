defmodule FountWorkshop do
  @moduledoc "Writer-controlled screenplay candidates and explicit review decisions."
  alias FountWorkshop.Develop
  alias FountWorkshop.Review
  alias FountWorkshop.Session
  alias FountWorkshop.Share
  alias FountWorkshop.TableRead
  alias FountWorkshop.Usefulness

  @doc "Provider-free Phase-9 workflow/resource preflight. It does not start a session or call a model."
  def preflight(model, request, opts \\ []), do: Session.preflight(model, request, opts)

  def develop(repo, key, brief, client, opts \\ []),
    do: Develop.run(repo, key, brief, client, opts)

  def review(repo, candidate_id), do: Review.packet(repo, candidate_id)

  def accept(
        repo,
        candidate_id,
        %Fount.Writing.Approval{} = approval,
        %Fount.Writing.Authority{} = authority
      ),
      do: Review.accept(repo, candidate_id, approval, authority)

  def accept(_repo, _candidate_id, _legacy_expected_revision, _legacy_review),
    do: {:error, :authorized_approval_required}

  def reject(repo, candidate_id, actor), do: Review.reject(repo, candidate_id, actor)

  @doc "Builds a provider-free human table-read packet from canonical screenplay material."
  def read_packet(model, selection \\ %{"whole_screenplay" => true}, opts \\ []),
    do: TableRead.packet(model, selection, opts)

  @doc "Exports a clean selected reader copy from canonical screenplay material."
  def share(model, selection, directory, opts \\ []),
    do: Share.export(model, selection, directory, opts)

  @doc "Records one explicit writer-usefulness observation without scoring the screenplay."
  def usefulness_record(attrs), do: Usefulness.record(attrs)

  @doc "Packages writer-usefulness observations without ranking workflow conditions."
  def usefulness_report(records, opts \\ []), do: Usefulness.report(records, opts)
end
