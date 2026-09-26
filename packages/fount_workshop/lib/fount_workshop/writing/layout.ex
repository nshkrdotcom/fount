defmodule FountWorkshop.Writing.Layout do
  @moduledoc false
  alias Fount.Screenplay.Model

  def compare(base, candidate, services, opts) do
    if Keyword.get(opts, :render, false) do
      render_comparison(
        base,
        candidate,
        services[:renderer],
        Keyword.get(opts, :output_dir),
        opts
      )
    else
      {:ok, nil, nil}
    end
  end

  defp render_comparison(_, _, renderer, output, _opts)
       when is_nil(renderer) or not is_binary(output),
       do: {:error, :explicit_renderer_and_output_directory_required}

  defp render_comparison(base, candidate, renderer, output, opts) do
    base_path = Path.join(output, "base-" <> base.revision.id <> ".pdf")
    candidate_path = Path.join(output, "candidate-" <> candidate["id"] <> ".pdf")

    with {:ok, before} <- render(renderer, base, base_path, opts),
         {:ok, after_pdf} <- render(renderer, candidate["screenplay"], candidate_path, opts) do
      same =
        before[:settings_sha256] != nil and
          before[:settings_sha256] == after_pdf[:settings_sha256]

      data = %{
        "base_pages" => before.pages,
        "candidate_pages" => after_pdf.pages,
        "same_settings" => same,
        "saved_pages" => if(same, do: before.pages - after_pdf.pages, else: nil),
        "base_pdf" => Model.plain(before),
        "candidate_pdf" => Model.plain(after_pdf)
      }

      report =
        FountProbe.Report.new(candidate["screenplay"], "layout_compare", %{}, %{
          source_revision_ids: [base.revision.id, candidate["screenplay"].revision.id],
          data: data,
          status: if(same, do: "complete", else: "partial"),
          provenance: %{"renderer" => "actual_file_calls"}
        })

      {:ok, data, report}
    end
  end

  def render(renderer, model, path, opts) when is_function(renderer, 3),
    do: renderer.(model, path, opts)

  def render(renderer, model, path, opts) when is_atom(renderer),
    do: renderer.export(model, path, opts)

  def render(_, _, _, _), do: {:error, :invalid_renderer}
end
