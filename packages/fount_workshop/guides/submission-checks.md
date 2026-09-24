# Submission Checks

Different screenplay competitions and coverage platforms enforce strict mechanical submission criteria. Submitting a script with contact information on the title page to a blind competition, or exceeding page count ranges, can lead to immediate disqualification.

Fount Workshop provides **dated submission profiles** to mechanically audit rendered PDFs prior to upload.

---

## 1. Mechanical Audit vs. Writer Eligibility

Fount Workshop maintains a strict distinction between **measurable mechanical properties** and **legal/authorship eligibility**:
* **What Fount Can Check:** Exact page count ranges, paper dimensions, font embedding, trailing blank pages, and title-page contact anonymity.
* **What Requires Writer Review:** Ownership of underlying rights, residency or guild eligibility, and compliance with venue-specific AI policies.

---

## 2. Supported Submission Profiles

Profiles are loaded using `FountWorkshop.Submission.profile/1`:

### The Black List (`:black_list`)
* **Page Bounds:** Flexible (no arbitrary artificial minimum or maximum imposed).
* **Anonymity:** Not required (author and contact information permitted).
* **Focus:** Ensures valid US Letter PDF with embedded Courier Prime and no blank pages.

### Academy Nicholl Fellowship (`:nicholl_2026_27`)
* **Page Bounds:** Strictly 80 to 125 pages.
* **Anonymity:** Strictly enforced. Disqualifies scripts with author name, phone number, email, or agency contact on the title page.
* **AI Policy Flag:** Highlights the Academy's rule prohibiting scripts containing AI-generated dialogue, characters, or scene description.

---

## 3. Running a Submission Check

Pass your script, the rendered PDF report, and the target profile to `FountWorkshop.Submission.check/4`:

```elixir
alias FountWorkshop.Submission
alias FountWorkshop.Export.PDF

# 1. Export the PDF
{:ok, pdf_report} = PDF.export(script, "exports/my_script.pdf")

# 2. Load the target profile
{:ok, profile} = Submission.profile(:nicholl_2026_27)

# 3. Audit the submission
audit = Submission.check(script, pdf_report, profile)
```

The resulting map provides a complete compliance audit:

```elixir
%{
  target: :nicholl_2026_27,
  status: :failed, # or :review_required
  checked_on: ~D[2026-09-23],
  source_url: "https://www.oscars.org/sites/oscars/files/...",
  mechanical_problems: [
    {:page_count_outside_target_range, 132, 80..125},
    :title_page_identifiers_present
  ],
  requires_writer_review: [
    :authorship_rights_and_current_rules,
    :verify_no_ai_generated_script_content
  ]
}
```

If `mechanical_problems` is empty, the status becomes `:review_required`, reminding the writer to verify qualitative rules before final submission.
