# PDF Export and Inspection

Screenplay formatting demands strict typographic and layout precision: standard 12pt Courier Prime, 1-inch top/bottom margins, exact dialogue and parenthetical tab indentations, orphan dialogue prevention, and dual-dialogue alignment.

Fount Workshop delegates layout to a pinned installation of **Afterwriting 1.17.3**, and then performs automated forensic inspection of the resulting PDF using Poppler utilities.

---

## 1. Why Dedicated Layout Engines Matter

Naïve pagination formulas (such as assuming 54 lines of Courier equals one page) consistently break on real scripts. As noted in Beat's pagination architecture:
* Dual-dialogue blocks require horizontal split alignment.
* Dialogue blocks cannot be orphaned across page breaks without inserting `(MORE)` and `(CONT'D)`.
* Long scene headings and transitions have distinct margin constraints.

By using Afterwriting, Fount Workshop guarantees industry-standard visual layout without bloating the pure Elixir core with a custom rendering engine.

---

## 2. Exporting Screenplays to PDF

You can export either an imported Fountain document or a canonical `Fount.Screenplay`:

```elixir
alias FountWorkshop.Export.PDF

# Export script to PDF
{:ok, report} = PDF.export(script, "priv/exports/feature.pdf")
```

The returned `report` contains full structural and cryptographic inspection metadata:

```elixir
%{
  path: "/path/to/priv/exports/feature.pdf",
  pages: 104,
  page_size: :us_letter,
  courier_prime?: true,
  blank_pages: [],
  bytes: 142890,
  sha256: "8e7b1a...",
  source_revision: "rev_04f8...",
  renderer: "afterwriting 1.17.3"
}
```

---

## 3. Automated Forensic Inspection

Every generated PDF is inspected using system tools (`pdfinfo`, `pdffonts`, and `pdftotext`):

1. **Page Geometry:** Confirms the document conforms to US Letter specifications (8.5 × 11 inches).
2. **Font Embedding:** Inspects embedded font tables to verify authentic **Courier Prime** rather than fallback system monospace fonts.
3. **Blank Page Detection:** Scans text extractions across all pages to catch accidental trailing blank pages or spacing overflows.
4. **Revision Binding:** The export report cryptographically links the PDF hash to the exact screenplay revision ID from which it was generated.

---

## 4. Setup and System Prerequisites

To use the PDF export pipeline:

1. **Poppler Utilities:** Ensure `pdfinfo`, `pdffonts`, and `pdftotext` are installed on your host system:
   ```bash
   # Ubuntu / Debian
   sudo apt-get install poppler-utils

   # macOS (Homebrew)
   brew install poppler
   ```

2. **Pinned Afterwriting Renderer:** Install the pinned Afterwriting renderer in the workshop package:
   ```bash
   cd packages/fount_workshop
   npm ci
   ```
