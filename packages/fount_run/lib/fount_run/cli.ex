defmodule FountRun.CLI do
  @moduledoc """
  JSON CLI for the Phase-05 headless Run surface.

  Repo, ActorContext, provider services and the artifact root come only from a
  trusted host configuration. Command JSON contains work data, never identity,
  credentials, module names, PIDs or provider clients.
  """

  alias Fount.Screenplay.Model
  alias FountRun.ActorContext

  @exit_usage 2
  @exit_config 3
  @exit_conflict 4
  @exit_runtime 5

  @commands ~w(start show step decisions decide plan pause resume stop policy approve export)

  @spec run([String.t()], keyword()) :: {non_neg_integer(), map()}
  def run(argv, config \\ []) when is_list(argv) and is_list(config) do
    case parse(argv) do
      {:ok, %{help: true} = parsed} -> {0, %{"status" => "help", "usage" => usage(parsed[:command])}}
      {:ok, parsed} -> execute(parsed, config)
      {:error, reason} -> {@exit_usage, Map.put(error_payload(reason), "exit_code", @exit_usage)}
    end
  end

  def run(_argv, _config), do: {@exit_usage, error_payload(:invalid_cli_arguments)}

  @spec parse([String.t()]) :: {:ok, map()} | {:error, term()}
  def parse([]), do: {:ok, %{help: true, command: nil}}

  def parse(["--help"]), do: {:ok, %{help: true, command: nil}}
  def parse([command | rest]) when command in @commands do
    {opts, args, invalid} =
      OptionParser.parse(rest,
        strict: [
          help: :boolean,
          input: :string,
          expected_version: :integer,
          command_id: :string,
          destination: :string,
          pdf: :boolean,
          table_read: :boolean
        ]
      )

    with [] <- invalid,
         :ok <- no_duplicate_options(rest) do
      if opts[:help] do
        {:ok, %{command: command, help: true}}
      else
        with {:ok, parsed} <- parse_command(command, args, opts) do
          {:ok, Map.put(parsed, :help, false)}
        end
      end
    else
      [_ | _] -> {:error, :invalid_options}
      {:error, _} = error -> error
    end
  end

  def parse([_unknown | _]), do: {:error, :unknown_command}

  def execute(%{command: command} = parsed, config) do
    with {:ok, runtime} <- runtime_config(config),
         {:ok, value} <- execute_command(command, parsed, runtime) do
      {0, %{"status" => "ok", "result" => Model.plain(value)}}
    else
      {:error, reason} -> {exit_code(reason), error_payload(reason)}
      {:partial, reason, details} ->
        {@exit_runtime,
         %{
           "status" => "partial",
           "error" => reason_name(reason),
           "details" => Model.plain(details),
           "exit_code" => @exit_runtime
         }}
    end
  end

  defp parse_command("start", [], opts), do: require_input("start", opts)
  defp parse_command("show", [run_id], _opts), do: {:ok, %{command: "show", run_id: run_id}}
  defp parse_command("step", [run_id], _opts), do: {:ok, %{command: "step", run_id: run_id}}
  defp parse_command("decisions", [run_id], _opts), do: {:ok, %{command: "decisions", run_id: run_id}}
  defp parse_command("decide", [decision_id], opts), do: require_input("decide", opts, decision_id: decision_id)

  defp parse_command("plan", [run_id], opts) do
    with {:ok, parsed} <- require_input("plan", opts, run_id: run_id),
         :ok <- require_positive_version(opts[:expected_version]),
         :ok <- require_nonempty(opts[:command_id], :command_id_required) do
      {:ok,
       Map.merge(parsed, %{
         expected_version: opts[:expected_version],
         command_id: opts[:command_id]
       })}
    else
      false -> {:error, :invalid_control_options}
      {:error, _} = error -> error
    end
  end

  defp parse_command("policy", [run_id], opts) do
    with {:ok, parsed} <- require_input("policy", opts, run_id: run_id),
         :ok <- require_positive_version(opts[:expected_version]),
         :ok <- require_nonempty(opts[:command_id], :command_id_required) do
      {:ok,
       Map.merge(parsed, %{
         expected_version: opts[:expected_version],
         command_id: opts[:command_id]
       })}
    else
      false -> {:error, :invalid_control_options}
      {:error, _} = error -> error
    end
  end

  defp parse_command(command, [run_id], _opts) when command in ~w(pause resume stop),
    do: {:ok, %{command: command, run_id: run_id}}

  defp parse_command("approve", [run_id], opts), do: require_input("approve", opts, run_id: run_id)

  defp parse_command("export", [run_id], opts) do
    if nonempty?(opts[:destination]) do
      {:ok,
       %{
         command: "export",
         run_id: run_id,
         destination: opts[:destination],
         pdf: opts[:pdf] || false,
         table_read: opts[:table_read] || false
       }}
    else
      {:error, :destination_required}
    end
  end

  defp parse_command(_command, _args, opts) do
    if opts[:help], do: {:ok, %{command: nil}}, else: {:error, :invalid_command_arguments}
  end

  defp require_input(command, opts, additions \\ []) do
    if nonempty?(opts[:input]),
      do: {:ok, additions |> Map.new() |> Map.merge(%{command: command, input: opts[:input]})},
      else: {:error, :input_required}
  end

  defp require_positive_version(value) when is_integer(value) and value > 0, do: :ok
  defp require_positive_version(_value), do: {:error, :expected_version_required}

  defp require_nonempty(value, error) do
    if nonempty?(value), do: :ok, else: {:error, error}
  end

  defp execute_command("start", parsed, runtime) do
    with {:ok, payload} <- json_file(parsed.input),
         true <- is_map(payload) or {:error, :input_must_be_object} do
      {attrs, first_step} = start_payload(payload)

      with {:ok, run} <- FountRun.start_run(runtime.repo, attrs, runtime.context),
           {:ok, result} <- maybe_enqueue_first_step(runtime.repo, run, first_step, runtime.context) do
        {:ok, result}
      end
    else
      false -> {:error, :input_must_be_object}
      {:error, _} = error -> error
    end
  end

  defp execute_command("show", parsed, runtime),
    do: FountRun.get_run(runtime.repo, parsed.run_id, runtime.context)

  defp execute_command("step", parsed, runtime) do
    services = Map.put(runtime.services, :actor_context, runtime.context)
    FountRun.step(runtime.repo, parsed.run_id, services, runtime.step_options)
  end

  defp execute_command("decisions", parsed, runtime) do
    with {:ok, progress} <- FountRun.progress(runtime.repo, parsed.run_id, runtime.context) do
      {:ok,
       %{
         "run" => progress["run"],
         "decisions" => progress["decisions"],
         "approval_attempts" => progress["approval_attempts"]
       }}
    end
  end

  defp execute_command("decide", parsed, runtime) do
    with {:ok, response} <- json_object(parsed.input) do
      FountRun.submit_decision(runtime.repo, parsed.decision_id, response, runtime.context)
    end
  end

  defp execute_command("plan", parsed, runtime) do
    with {:ok, plan} <- json_object(parsed.input) do
      FountRun.update_plan(runtime.repo, parsed.run_id, plan, runtime.context,
        expected_version: parsed.expected_version,
        command_id: parsed.command_id
      )
    end
  end

  defp execute_command("policy", parsed, runtime) do
    with {:ok, policy} <- json_object(parsed.input) do
      FountRun.update_policy(runtime.repo, parsed.run_id, policy, runtime.context,
        expected_version: parsed.expected_version,
        command_id: parsed.command_id
      )
    end
  end

  defp execute_command("pause", parsed, runtime),
    do: FountRun.pause_run(runtime.repo, parsed.run_id, runtime.context)

  defp execute_command("resume", parsed, runtime),
    do: FountRun.resume_run(runtime.repo, parsed.run_id, runtime.context)

  defp execute_command("stop", parsed, runtime),
    do: FountRun.stop_run(runtime.repo, parsed.run_id, runtime.context)

  defp execute_command("approve", parsed, runtime) do
    with {:ok, response} <- json_object(parsed.input) do
      FountRun.approve_run(runtime.repo, parsed.run_id, response, runtime.context)
    end
  end

  defp execute_command("export", parsed, runtime) do
    opts =
      [
        artifact_root: runtime.artifact_root,
        pdf: parsed.pdf,
        table_read: parsed.table_read
      ]
      |> maybe_put(:pdf_options, runtime.pdf_options)

    FountRun.deliver(runtime.repo, parsed.run_id, parsed.destination, runtime.context, opts)
  end

  defp runtime_config(config) do
    configured = Keyword.get(config, :runtime, Application.get_env(:fount_run, :cli, []))
    configured = if is_map(configured), do: Map.to_list(configured), else: configured

    repo = Keyword.get(configured, :repo)
    context = Keyword.get(configured, :actor_context)
    services = Keyword.get(configured, :services, %{})
    artifact_root = Keyword.get(configured, :artifact_root)
    step_options = Keyword.get(configured, :step_options, [])
    pdf_options = Keyword.get(configured, :pdf_options, [])

    cond do
      is_nil(repo) or not is_atom(repo) -> {:error, :cli_repo_not_configured}
      not match?(%ActorContext{}, context) -> {:error, :cli_actor_context_not_configured}
      not (is_map(services) or is_list(services)) -> {:error, :cli_services_invalid}
      not is_list(step_options) -> {:error, :cli_step_options_invalid}
      not is_list(pdf_options) -> {:error, :cli_pdf_options_invalid}
      true ->
        {:ok,
         %{
           repo: repo,
           context: context,
           services: if(is_list(services), do: Map.new(services), else: services),
           artifact_root: artifact_root,
           step_options: step_options,
           pdf_options: pdf_options
         }}
    end
  end

  defp start_payload(%{"run" => attrs} = payload) when is_map(attrs),
    do: {attrs, Map.get(payload, "first_step")}

  defp start_payload(payload), do: {payload, nil}

  defp maybe_enqueue_first_step(_repo, run, nil, _context), do: {:ok, run}

  defp maybe_enqueue_first_step(repo, run, step, context) when is_map(step) do
    with {:ok, queued} <- FountRun.enqueue_step(repo, run["id"], step, context) do
      {:ok, %{"run" => run, "first_step" => queued}}
    end
  end

  defp maybe_enqueue_first_step(_repo, _run, _step, _context), do: {:error, :invalid_first_step}

  defp json_object(path) do
    with {:ok, value} <- json_file(path), true <- is_map(value) do
      {:ok, value}
    else
      false -> {:error, :input_must_be_object}
      {:error, _} = error -> error
    end
  end

  defp json_file(path) do
    with {:ok, bytes} <- File.read(path),
         {:ok, decoded} <- Jason.decode(bytes) do
      {:ok, decoded}
    else
      {:error, %Jason.DecodeError{}} -> {:error, :invalid_json}
      {:error, _} -> {:error, :input_unreadable}
    end
  end

  defp no_duplicate_options(argv) do
    duplicates =
      argv
      |> Enum.flat_map(fn argument ->
        case Regex.run(~r/^--([a-z][a-z-]*)(?:=|$)/, argument) do
          [_, name] -> [name]
          _ -> []
        end
      end)
      |> Enum.frequencies()
      |> Enum.any?(fn {_name, count} -> count > 1 end)

    if duplicates, do: {:error, :duplicate_options}, else: :ok
  end

  defp maybe_put(opts, _key, []), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp nonempty?(value), do: is_binary(value) and String.trim(value) != ""

  defp exit_code(reason) do
    tag = reason_tag(reason)

    cond do
      tag in ~w(invalid_cli_arguments unknown_command invalid_options duplicate_options invalid_command_arguments input_required destination_required command_id_required expected_version_required invalid_json input_unreadable input_must_be_object invalid_first_step invalid_decision_response invalid_plan_update invalid_policy_update)a -> @exit_usage
      tag in ~w(cli_repo_not_configured cli_actor_context_not_configured cli_services_invalid cli_step_options_invalid cli_pdf_options_invalid artifact_root_not_configured unauthorized owner_required wrong_approver unregistered_approver)a -> @exit_config
      tag in ~w(already_resolved decision_conflict cross_run_decision stale_plan_version stale_policy_version stale_revision stale_plan stale_policy plan_invalidated policy_invalidated idempotency_conflict immutable_review_conflict immutable_approval_conflict stopped pause_requested stop_requested)a -> @exit_conflict
      true -> @exit_runtime
    end
  end

  defp error_payload(reason),
    do: %{"status" => "error", "error" => reason_name(reason), "exit_code" => exit_code(reason)}

  defp reason_name(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_name({reason, _}) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_name({reason, _, _}) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_name(_), do: "operation_failed"

  defp reason_tag(reason) when is_atom(reason), do: reason
  defp reason_tag({reason, _}) when is_atom(reason), do: reason
  defp reason_tag({reason, _, _}) when is_atom(reason), do: reason
  defp reason_tag(_), do: :operation_failed

  def usage(nil) do
    "mix fount.run <#{Enum.join(@commands, "|")}> [arguments] [--input JSON]"
  end

  def usage(command) do
    case command do
      "start" -> "mix fount.run start --input run.json"
      "show" -> "mix fount.run show RUN_ID"
      "step" -> "mix fount.run step RUN_ID"
      "decisions" -> "mix fount.run decisions RUN_ID"
      "decide" -> "mix fount.run decide DECISION_ID --input response.json"
      "plan" -> "mix fount.run plan RUN_ID --input plan.json --expected-version N --command-id KEY"
      "policy" -> "mix fount.run policy RUN_ID --input policy.json --expected-version N --command-id KEY"
      "pause" -> "mix fount.run pause RUN_ID"
      "resume" -> "mix fount.run resume RUN_ID"
      "stop" -> "mix fount.run stop RUN_ID"
      "approve" -> "mix fount.run approve RUN_ID --input exact-approval.json"
      "export" -> "mix fount.run export RUN_ID --destination RELATIVE_DIR [--pdf] [--table-read]"
      _ -> usage(nil)
    end
  end
end
