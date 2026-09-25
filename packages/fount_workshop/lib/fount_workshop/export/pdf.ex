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

    with {:ok, settings} <- settings(opts),
         :ok <- ensure_renderer(renderer),
         :ok <- File.mkdir_p(Path.dirname(output_path)) do
      input_path = output_path <> ".source-#{System.unique_integer([:positive])}.fountain"

      try do
        with :ok <- File.write(input_path, doc.source.raw, [:binary]),
             :ok <- run_renderer(renderer, input_path, output_path, settings),
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
             settings: settings,
             settings_sha256:
               Fount.Writing.CanonicalJSON.hash(
                 Map.put(settings, "renderer", "afterwriting 1.17.3")
               ),
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

  defp run_renderer(renderer, input_path, output_path, settings) do
    args =
      [
        "--source",
        input_path,
        "--pdf",
        output_path,
        "--overwrite"
      ] ++ Enum.flat_map(settings, fn {key, value} -> ["--setting", "#{key}=#{value}"] end)

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
           cond do
             String.contains?(info, "612 x 792 pts (letter)") -> :us_letter
             String.contains?(info, "(A4)") -> :a4
             true -> :other
           end,
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

  defp settings(opts) do
    allowed =
      ~w(print_profile font_family scenes_numbers print_notes use_dual_dialogue print_title_page)

    passed = Keyword.keys(opts) |> Enum.map(&to_string/1)
    # Other keywords are used by the caller's renderer or output orchestration.
    selected = Keyword.take(opts, Enum.map(allowed, &String.to_atom/1))

    values = %{
      "print_profile" => Keyword.get(selected, :print_profile, "usletter"),
      "font_family" => Keyword.get(selected, :font_family, "CourierPrime"),
      "scenes_numbers" => Keyword.get(selected, :scenes_numbers, "none"),
      "print_notes" => Keyword.get(selected, :print_notes, false),
      "use_dual_dialogue" => Keyword.get(selected, :use_dual_dialogue, true),
      "print_title_page" => Keyword.get(selected, :print_title_page, true)
    }

    valid =
      values["print_profile"] in ~w(usletter a4) and
        values["font_family"] in ~w(Courier CourierPrime CourierPrimeCyrillic) and
        values["scenes_numbers"] in ~w(none left right both) and
        Enum.all?(~w(print_notes use_dual_dialogue print_title_page), &is_boolean(values[&1]))

    if valid, do: {:ok, values}, else: {:error, {:invalid_pdf_settings, passed -- allowed}}
  end
end
