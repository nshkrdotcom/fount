defmodule FountWorkshop do
  @moduledoc "Writer-controlled screenplay candidates and explicit review decisions."

  alias FountWorkshop.{Develop, Review}

  def develop(repo, key, brief, client, opts \\ []),
    do: Develop.run(repo, key, brief, client, opts)

  def review(repo, candidate_id), do: Review.packet(repo, candidate_id)

  def accept(repo, candidate_id, expected_revision, writer_review),
    do: Review.accept(repo, candidate_id, expected_revision, writer_review)

  def reject(repo, candidate_id, actor), do: Review.reject(repo, candidate_id, actor)
end
