defmodule FountWorkshop.Export.PDF do
  @moduledoc "Renders an exact Fountain draft to a screenplay PDF using pinned Afterwriting."

  alias Fount.Document

  @renderer Path.expand("../../../node_modules/.bin/afterwriting", __DIR__)

  @spec export(Document.t() | Fount.Screenplay.t(), Path.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def export(document, output_path, opts \\ [])

  def export(%Fount.Screenplay{} = screenplay, output_path, opts) do
    source = Fount.Screenplay.to_fountain(screenplay, mode: :spec)

    with {:ok, doc} <- Fount.parse(source) do
      case export(doc, output_path, opts) do
        {:ok, report} -> {:ok, %{report | source_revision: screenplay.revision.id}}
        error -> error
      end
    end
  end

  def export(%Document{} = doc, output_path, opts) do
    renderer = Keyword.get(opts, :renderer, @renderer)
    output_path = Path.expand(output_path)

    with :ok <- ensure_renderer(renderer),
         :ok <- File.mkdir_p(Path.dirname(output_path)) do
      input_path = output_path <> ".source-#{System.unique_integer([:positive])}.fountain"

      try do
        with :ok <- File.write(input_path, doc.source.raw, [:binary]),
             :ok <- run_renderer(renderer, input_path, output_path),
             {:ok, pdf} <- File.read(output_path),
             :ok <- verify_pdf(pdf),
             {:ok, metadata} <- inspect_pdf(output_path) do
          {:ok,
           %{
             path: output_path,
             pages: metadata.pages,
             blank_pages: metadata.blank_pages,
             page_size: metadata.page_size,
             courier_prime?: metadata.courier_prime?,
             bytes: byte_size(pdf),
             sha256: Fount.ID.hash(pdf),
             source_revision: doc.revision.id,
             renderer: "afterwriting 1.17.3",
             settings_sha256:
               Fount.Writing.CanonicalJSON.hash(%{
                 "renderer" => "afterwriting 1.17.3",
                 "print_profile" => "usletter",
                 "font_family" => "CourierPrime",
                 "scene_numbers" => "none",
                 "print_notes" => false,
                 "dual_dialogue" => true
               }),
             source_sha256: :crypto.hash(:sha256, doc.source.raw) |> Base.encode16(case: :lower)
           }}
        end
      after
        File.rm(input_path)
      end
    end
  end

  defp ensure_renderer(path) do
    if File.regular?(path), do: :ok, else: {:error, :renderer_not_installed}
  end

  defp run_renderer(renderer, input_path, output_path) do
    args = [
      "--source",
      input_path,
      "--pdf",
      output_path,
      "--overwrite",
      "--setting",
      "print_profile=usletter",
      "--setting",
      "font_family=CourierPrime",
      "--setting",
      "scenes_numbers=none",
      "--setting",
      "print_notes=false",
      "--setting",
      "use_dual_dialogue=true"
    ]

    case System.cmd(renderer, args, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, status} -> {:error, {:render_failed, status, output}}
    end
  end

  defp verify_pdf("%PDF-" <> _), do: :ok
  defp verify_pdf(_), do: {:error, :invalid_pdf}

  defp inspect_pdf(path) do
    with {:ok, info} <- run_tool("pdfinfo", path),
         {:ok, fonts} <- run_tool("pdffonts", path),
         {:ok, extracted} <- extract_text(path),
         {:ok, pages} <- parse_page_count(info) do
      {:ok,
       %{
         pages: pages,
         blank_pages: blank_pages(extracted, pages),
         page_size:
           if(String.contains?(info, "612 x 792 pts (letter)"), do: :us_letter, else: :other),
         courier_prime?: String.contains?(fonts, "CourierPrime")
       }}
    end
  end

  defp extract_text(path) do
    case System.find_executable("pdftotext") do
      nil ->
        {:error, {:tool_not_installed, "pdftotext"}}

      executable ->
        case System.cmd(executable, ["-layout", path, "-"], stderr_to_stdout: true) do
          {output, 0} -> {:ok, output}
          {output, status} -> {:error, {:tool_failed, "pdftotext", status, output}}
        end
    end
  end

  defp blank_pages(text, count) do
    text
    |> String.split("\f")
    |> Enum.take(count)
    |> Enum.with_index(1)
    |> Enum.filter(fn {page, _index} -> String.trim(page) == "" end)
    |> Enum.map(&elem(&1, 1))
  end

  defp run_tool(name, path) do
    case System.find_executable(name) do
      nil ->
        {:error, {:tool_not_installed, name}}

      executable ->
        case System.cmd(executable, [path], stderr_to_stdout: true) do
          {output, 0} -> {:ok, output}
          {output, status} -> {:error, {:tool_failed, name, status, output}}
        end
    end
  end

  defp parse_page_count(output) do
    case Regex.run(~r/^Pages:\s+(\d+)$/m, output, capture: :all_but_first) do
      [number] -> {:ok, String.to_integer(number)}
      _ -> {:error, :page_count_unavailable}
    end
  end
end
