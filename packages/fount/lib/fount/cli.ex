defmodule Fount.CLI do
  @moduledoc "Core import, exact revision inspection, export and history commands."
  alias Fount.CLI.Support, as: S
  @flags [key: :string, format: :string, output: :string, revision: :string]

  def run(command, argv) do
    with {:ok, opts, args} <- S.parse(argv, @flags) do
      if opts[:help] do
        {:ok, %{"usage" => help(command)}}
      else
        with :ok <- S.required(opts, [:key]), :ok <- arguments(command, args, opts), {:ok, repo} <- S.connect() do
          dispatch(command, args, opts, repo)
        end
      end
    end
  end

  defp dispatch("import", [path], opts, repo) do
    with {:ok, bytes} <- File.read(path),
         {:ok, model, diagnostics} <- Fount.Interchange.read(bytes, opts[:format], cast_resolution: :literal_cues),
         {:ok, root} <-
           Fount.Persistence.create(repo, opts[:key], model,
             provenance: %{
               "import_file" => Path.basename(path),
               "diagnostics" => Fount.Screenplay.Model.plain(diagnostics)
             }
           ) do
      {:ok, summary(root)}
    end
  end

  defp dispatch("inspect", [], opts, repo) do
    with {:ok, model} <- S.load(repo, opts) do
      {:ok,
       Map.merge(summary(model), %{
         "scenes" => Fount.Screenplay.Model.plain(model.ir.scenes),
         "elements" => Fount.Screenplay.Model.plain(model.ir.elements),
         "characters" => Fount.Screenplay.Model.plain(Map.values(model.cast)),
         "authored_items" => model.authored_items,
         "dialogue_blocks" => Fount.Screenplay.Model.plain(model.ir.dialogue_blocks)
       })}
    end
  end

  defp dispatch("export", [], opts, repo) do
    with {:ok, model} <- S.load(repo, opts),
         {:ok, result} <- Fount.Interchange.write(model, opts[:format], include_source: true),
         :ok <- File.mkdir_p(Path.dirname(opts[:output])),
         :ok <- File.write(opts[:output], result.data),
         {:ok, _} <- S.write_json(opts[:output] <> ".fidelity.json", Map.delete(Map.from_struct(result), :data)) do
      {:ok, %{"path" => opts[:output], "revision_id" => model.revision.id, "losses" => result.losses}}
    end
  end

  defp dispatch("history", [], opts, repo) do
    with {:ok, model} <- S.load(repo, opts) do
      case Fount.Persistence.history(repo, model.id) do
        {:error, _} = error -> error
        rows -> {:ok, %{"screenplay_id" => model.id, "accepted_head" => model.revision.id, "revisions" => rows}}
      end
    end
  end

  defp dispatch(_, _, _, _), do: {:error, :unknown_core_command}

  def summary(model),
    do: %{
      "screenplay_id" => model.id,
      "revision_id" => model.revision.id,
      "content_hash" => model.revision.content_hash,
      "scenes" => length(model.ir.scenes),
      "elements" => length(model.ir.elements)
    }

  defp arguments("import", [_], opts), do: format(opts)

  defp arguments("export", [], opts) do
    with :ok <- S.required(opts, [:output]), :ok <- format(opts), do: :ok
  end

  defp arguments(command, [], _) when command in ["inspect", "history"], do: :ok
  defp arguments(_, _, _), do: {:error, :invalid_positional_arguments}
  defp format(opts), do: if(opts[:format] in ~w(fountain fdx json), do: :ok, else: {:error, :format_required})
  defp help("import"), do: "mix fount.import INPUT --key KEY --format fountain|fdx|json [--json]"
  defp help("inspect"), do: "mix fount.inspect --key KEY [--revision UUID] [--json]"
  defp help("history"), do: "mix fount.history --key KEY [--json]"
  defp help("export"), do: "mix fount.export --key KEY --output PATH --format fountain|fdx|json [--revision UUID]"
end
