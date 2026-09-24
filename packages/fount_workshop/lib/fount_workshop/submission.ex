defmodule FountWorkshop.Submission do
  @moduledoc "Dated, target-specific mechanical checks for a rendered screenplay PDF."

  @nicholl_url "https://www.oscars.org/sites/oscars/files/2026-06/2026-2027%20Nicholl%20Rules%20Terms%20and%20Conditions%20%281%29.pdf"
  @black_list_url "https://help.blcklst.com/kb/guide/en/writers-pROPvK6l0J/Steps/2724678"

  @spec profile(atom()) :: {:ok, map()} | {:error, :unknown_profile}
  def profile(:nicholl_2026_27) do
    {:ok,
     %{
       target: :nicholl_2026_27,
       checked_on: ~D[2026-09-23],
       source_url: @nicholl_url,
       page_range: 80..125,
       anonymous?: true,
       ai_generated_text_allowed?: false
     }}
  end

  def profile(:black_list) do
    {:ok,
     %{
       target: :black_list,
       checked_on: ~D[2026-09-23],
       source_url: @black_list_url,
       page_range: nil,
       anonymous?: false,
       ai_generated_text_allowed?: :unknown
     }}
  end

  def profile(_), do: {:error, :unknown_profile}

  @spec check(Fount.Document.t() | Fount.Screenplay.t(), map(), map(), keyword()) :: map()
  def check(doc, pdf_report, profile, opts \\ []) do
    problems =
      []
      |> check_revision(doc, pdf_report)
      |> check_pages(pdf_report, profile)
      |> check_blank_pages(pdf_report)
      |> check_format(pdf_report)
      |> check_title(doc, profile)

    review =
      [:authorship_rights_and_current_rules]
      |> check_ai_policy(profile, Keyword.get(opts, :ai_origin?, :unknown))

    %{
      target: profile.target,
      checked_on: profile.checked_on,
      source_url: profile.source_url,
      mechanical_problems: Enum.reverse(problems),
      requires_writer_review: Enum.reverse(review),
      status: if(problems == [], do: :review_required, else: :failed)
    }
  end

  @doc "Checks a saved filesystem draft and includes recorded accepted model edits."
  @spec check_saved(struct(), String.t(), Fount.Document.t(), map(), map()) :: map()
  def check_saved(%Fount.Store.Filesystem{} = store, key, doc, pdf_report, profile) do
    ai_origin = if FountWorkshop.Acceptance.any_for?(store, key), do: true, else: :unknown
    check(doc, pdf_report, profile, ai_origin?: ai_origin)
  end

  defp check_revision(problems, doc, %{source_revision: revision}) do
    if revision == doc.revision.id, do: problems, else: [:pdf_source_revision_mismatch | problems]
  end

  defp check_revision(problems, _doc, _report), do: [:missing_pdf_source_revision | problems]

  defp check_pages(problems, %{pages: pages}, %{page_range: range}) when is_integer(pages) do
    cond do
      pages < 1 -> [:empty_pdf | problems]
      is_nil(range) -> problems
      pages in range -> problems
      true -> [{:page_count_outside_target_range, pages, range} | problems]
    end
  end

  defp check_pages(problems, _report, _profile), do: [:missing_page_count | problems]

  defp check_blank_pages(problems, %{blank_pages: []}), do: problems

  defp check_blank_pages(problems, %{blank_pages: pages}) when is_list(pages),
    do: [{:blank_pdf_pages, pages} | problems]

  defp check_blank_pages(problems, _report), do: [:blank_pages_not_checked | problems]

  defp check_format(problems, pdf_report) do
    problems =
      if pdf_report[:page_size] == :us_letter, do: problems, else: [:non_letter_paper | problems]

    if pdf_report[:courier_prime?] == true,
      do: problems,
      else: [:courier_prime_not_confirmed | problems]
  end

  defp check_title(problems, %{ir: %{title_page: title_page}}, %{anonymous?: true}) do
    entries = if title_page, do: title_page.entries, else: []

    if Enum.any?(entries, fn entry ->
         String.downcase(entry.key) in ["author", "authors", "contact"]
       end) do
      [:title_page_identifiers_present | problems]
    else
      problems
    end
  end

  defp check_title(problems, _doc, _profile), do: problems

  defp check_ai_policy(review, %{ai_generated_text_allowed?: false}, true),
    do: [:known_ai_origin_conflicts_with_target_rule | review]

  defp check_ai_policy(review, %{ai_generated_text_allowed?: false}, _),
    do: [:verify_no_ai_generated_script_content | review]

  defp check_ai_policy(review, _profile, _), do: review
end
