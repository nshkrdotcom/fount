defmodule Fount.CLI.Support do
  @moduledoc "Strict launcher utilities. Merely parsing a command never opens PostgreSQL or contacts a provider."

  def parse(argv, options) do
    {opts, args, invalid} = OptionParser.parse(argv, strict: Keyword.merge([help: :boolean, json: :boolean], options))

    duplicates =
      argv
      |> Enum.flat_map(fn argument ->
        case Regex.run(~r/^--([a-z][a-z-]*)(?:=|$)/, argument) do
          [_, name] -> [name]
          _ -> []
        end
      end)
      |> Enum.frequencies()
      |> Enum.filter(fn {_, count} -> count > 1 end)

    cond do
      invalid != [] -> {:error, {:invalid_options, invalid}}
      duplicates != [] -> {:error, {:duplicate_options, Enum.map(duplicates, &elem(&1, 0))}}
      true -> {:ok, opts, args}
    end
  end

  def required(opts, names) do
    missing =
      Enum.filter(names, fn name ->
        value = opts[name]
        not is_binary(value) or String.trim(value) == ""
      end)

    if missing == [], do: :ok, else: {:error, {:required_options, missing}}
  end

  def ids(value) when is_binary(value) do
    values = value |> String.split(",", trim: false) |> Enum.map(&String.trim/1)

    if values != [] and Enum.all?(values, &(&1 != "")) and length(Enum.uniq(values)) == length(values),
      do: {:ok, values},
      else: {:error, :nonempty_unique_ids_required}
  end

  def ids(_), do: {:error, :ids_required}

  def json_file(path) do
    with {:ok, bytes} <- File.read(path), {:ok, value} <- Jason.decode(bytes) do
      {:ok, value}
    end
  end

  def write_json(path, value) do
    with :ok <- File.mkdir_p(Path.dirname(path)),
         {:ok, bytes} <- Jason.encode(Fount.Screenplay.Model.plain(value), pretty: true),
         :ok <- File.write(path, bytes <> "\n") do
      {:ok, path}
    end
  end

  def connect do
    case System.get_env("FOUNT_DATABASE_URL") do
      url when is_binary(url) and url != "" ->
        case Fount.Repo.start_link(url: url, pool_size: 5) do
          {:ok, _pid} -> {:ok, Fount.Repo}
          {:error, {:already_started, _pid}} -> {:ok, Fount.Repo}
          {:error, _} -> {:error, :postgres_connection_failed}
        end

      _ ->
        {:error, :explicit_fount_database_url_required}
    end
  end

  def load(repo, opts) do
    with :ok <- required(opts, [:key]), {:ok, head} <- Fount.Persistence.load(repo, opts[:key]) do
      case opts[:revision] do
        nil -> {:ok, head}
        id -> Fount.Persistence.load_revision(repo, head.id, id)
      end
    end
  end

  def finish!({:ok, value}) do
    Mix.shell().info(Jason.encode!(Fount.Screenplay.Model.plain(value), pretty: true))
  end

  def finish!({:error, reason, session}) do
    Mix.shell().error(
      Jason.encode!(%{"status" => "partial", "session_id" => session["id"], "progress" => session["progress"]},
        pretty: true
      )
    )

    Mix.raise("Fount operation incomplete: " <> error_name(reason))
  end

  def finish!({:error, reason}), do: Mix.raise("Fount operation failed: " <> error_name(reason))
  def finish!(other), do: Mix.raise("Unexpected Fount result: " <> error_name(other))

  defp error_name(%{__struct__: module}), do: inspect(module)
  defp error_name(reason) when is_atom(reason), do: to_string(reason)
  defp error_name(reason) when is_tuple(reason), do: reason |> elem(0) |> error_name()
  defp error_name(_), do: "see saved review or request validation result"
end
