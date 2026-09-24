defmodule FountWorkshop.SubmissionTest do
  use ExUnit.Case, async: true

  test "target-specific checks do not invent a universal page range or certify eligibility" do
    doc = Fount.parse!("Title: Film\nAuthor: A Writer\n\nINT. ROOM - DAY\n")

    pdf = %{
      pages: 90,
      blank_pages: [],
      source_revision: doc.revision.id,
      page_size: :us_letter,
      courier_prime?: true
    }

    {:ok, nicholl} = FountWorkshop.Submission.profile(:nicholl_2026_27)
    {:ok, black_list} = FountWorkshop.Submission.profile(:black_list)

    nicholl_result = FountWorkshop.Submission.check(doc, pdf, nicholl, ai_origin?: true)
    assert :title_page_identifiers_present in nicholl_result.mechanical_problems
    assert :known_ai_origin_conflicts_with_target_rule in nicholl_result.requires_writer_review
    assert nicholl_result.status == :failed

    black_list_result = FountWorkshop.Submission.check(doc, %{pdf | pages: 70}, black_list)
    assert black_list_result.mechanical_problems == []
    assert black_list_result.status == :review_required

    refute Enum.any?(
             black_list_result.mechanical_problems,
             &match?({:page_count_outside_target_range, _, _}, &1)
           )
  end
end
