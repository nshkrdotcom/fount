defmodule Fount.Intelligence.Runner.Architecture do
  @moduledoc """
  Repository-owned source and BEAM dependency gate for the four-package workspace.

  The explicit rules catch common architectural shortcuts; this is not a general
  proof of purity. Runtime QC also runs deterministic replay tests and reviews
  `mix xref` compile/export/runtime coupling. Source-only checks never imply a
  successful compiled dependency check.
  """
  @pure ~w(StoryWorld Temporal Reader Diagnosis Capabilities)
  @shell ~w(Acquisition Playbooks Runner Persistence Reporting)
  @leaves ~w(Observation MeasurementResult Distribution EvidenceRef TargetRef Error Context
             Context.EntityRef Context.Fact Context.Belief Context.Relation Context.Turn
             Context.Quantity Context.TemporalRef)
  @effects ~w(File IO System Application Code GenServer Agent Process Task Supervisor
               DynamicSupervisor Registry Ecto Inference SystemOneSDK Req Finch Mint
               HTTPoison Tesla Postgrex DBConnection Fount.Repo Fount.Persistence)
  @otp_effects [
    :rand,
    :random,
    :ets,
    :dets,
    :mnesia,
    :persistent_term,
    :os,
    :file,
    :code,
    :httpc,
    :gen_tcp,
    :gen_udp,
    :ssl,
    :inet,
    :timer
  ]
  @erlang_effects ~w(system_time monotonic_time timestamp unique_integer self spawn
                     spawn_link spawn_monitor send send_after start_timer make_ref
                     get put erase process_flag register unregister apply)a
  @apps ~w(fount fount_observe fount_intelligence fount_workshop)

  @doc "Checks a source string, resolving ordinary aliases/imports and captures."
  def source_violations(source, path) when is_binary(source) do
    case Code.string_to_quoted(source, columns: true) do
      {:ok, ast} ->
        initial = state(path)
        {_ast, state} = Macro.traverse(ast, initial, &visit/2, &leave/2)
        state.violations |> Enum.reverse() |> Enum.uniq()

      {:error, {location, error, token}} ->
        [
          violation(
            "source_parse",
            path,
            if(is_integer(location), do: location, else: Keyword.get(location, :line, 0)),
            inspect({error, token})
          )
        ]
    end
  end

  @doc "Checks physical ownership, source dependencies and (unless disabled) compiled imports."
  def check(root, opts \\ []) do
    root = Path.expand(root)
    sources = Path.wildcard(Path.join(root, "packages/*/lib/**/*.ex")) |> Enum.sort()

    source_results =
      Enum.flat_map(sources, &source_violations(File.read!(&1), Path.relative_to(&1, root)))

    expected = source_modules(sources, root)
    graph_errors = physical_graph(root)
    compiled? = not Keyword.get(opts, :source_only, false)

    {compiled_errors, missing, checked} =
      if compiled?, do: compiled_graph(root, expected), else: {[], [], 0}

    errors = graph_errors ++ source_results ++ compiled_errors

    %{
      "status" => if(errors == [] and missing == [], do: "pass", else: "fail"),
      "mode" => if(compiled?, do: "source_and_compiled", else: "source_only"),
      "packages" => @apps,
      "source_files" => length(sources),
      "compiled_modules_checked" => checked,
      "compiled_modules_missing" => missing,
      "violations" => errors,
      "limitations" => [
        "Not a general purity theorem; runtime replay and xref review remain required."
      ]
    }
  end

  defp state(path),
    do: %{module: nil, aliases: %{}, stack: [], names: [], violations: [], path: path}

  defp visit({:defmodule, _, [name, _]} = ast, state) do
    full = declared_module(name, state)
    frame = {state.module, state.aliases}
    next = %{state | module: full, stack: [frame | state.stack], names: [full | state.names]}
    {ast, next}
  end

  defp visit({:alias, _, [{{:., _, [base, :{}]}, _, children}]} = ast, state) do
    parent = module_name(base, state.aliases)

    aliases =
      Enum.reduce(children, state.aliases, fn child, acc ->
        full = join_module(parent, module_name(child, acc))
        Map.put(acc, full |> String.split(".") |> List.last(), full)
      end)

    {ast, %{state | aliases: aliases}}
  end

  defp visit({:alias, _, [name | options]} = ast, state) do
    full = module_name(name, state.aliases)

    short =
      case options do
        [[as: as_name]] -> module_name(as_name, %{})
        _ -> full && full |> String.split(".") |> List.last()
      end

    aliases = if full && short, do: Map.put(state.aliases, short, full), else: state.aliases
    {ast, %{state | aliases: aliases}}
  end

  defp visit({kind, meta, [name | _]} = ast, state) when kind in [:import, :use, :require] do
    dependency = module_name(name, state.aliases)
    {ast, check_dependency(state, dependency, nil, nil, meta[:line] || 0)}
  end

  defp visit({:%, meta, [name, _]} = ast, state) do
    {ast, check_dependency(state, module_name(name, state.aliases), nil, nil, meta[:line] || 0)}
  end

  defp visit({{:., _, [receiver, function]}, meta, args} = ast, state) when is_list(args) do
    dependency =
      if match?({:__MODULE__, _, _}, receiver),
        do: state.module,
        else: module_name(receiver, state.aliases)

    line = meta[:line] || 0

    next =
      if is_nil(dependency) and pure?(state.module) do
        # The zero-argument AST shape is also used for ordinary map.field access.
        # Parenthesized dynamic invocation has :no_parens absent/false.
        if args == [] and meta[:no_parens] == true,
          do: state,
          else: add(state, "pure_dynamic_dispatch", line, "dynamic receiver")
      else
        check_dependency(state, dependency, function, length(args), line)
      end

    {ast, next}
  end

  defp visit({name, meta, args} = ast, state) when is_atom(name) and is_list(args) do
    state =
      if pure?(state.module) and
           name in [:apply, :spawn, :spawn_link, :spawn_monitor, :send, :self, :make_ref],
         do: add(state, "pure_forbidden_mfa", meta[:line] || 0, "#{name}/#{length(args)}"),
         else: state

    {ast, state}
  end

  defp visit(ast, state), do: {ast, state}

  defp leave({:defmodule, _, _} = ast, %{stack: [{parent, aliases} | stack]} = state) do
    # defmodule also establishes a lexical alias for its child in the parent.
    aliases =
      if parent && state.module,
        do: Map.put(aliases, List.last(String.split(state.module, ".")), state.module),
        else: aliases

    {ast, %{state | module: parent, aliases: aliases, stack: stack}}
  end

  defp leave(ast, state), do: {ast, state}

  defp declared_module({:__aliases__, _, [:"Elixir" | rest]}, _state), do: Enum.join(rest, ".")

  defp declared_module({:__aliases__, _, [child]}, %{module: parent})
       when is_atom(child) and not is_nil(parent),
       do: parent <> "." <> Atom.to_string(child)

  defp declared_module(name, state), do: module_name(name, state.aliases)

  defp module_name({:__aliases__, _, parts}, aliases) do
    [first | rest] = Enum.map(parts, &Atom.to_string/1)
    Enum.join([Map.get(aliases, first, first) | rest], ".") |> String.trim_leading("Elixir.")
  end

  defp module_name(atom, _) when is_atom(atom),
    do: Atom.to_string(atom) |> String.trim_leading("Elixir.")

  defp module_name(_, _), do: nil
  defp join_module(nil, child), do: child
  defp join_module(parent, child), do: parent <> "." <> child

  defp pure?(module) when is_binary(module),
    do: Enum.any?(@pure, &prefix?(module, "Fount.Intelligence." <> &1))

  defp pure?(_), do: false
  defp prefix?(value, prefix), do: value == prefix or String.starts_with?(value, prefix <> ".")
  defp package(path), do: Enum.find(@apps, &String.contains?(path, "packages/" <> &1 <> "/"))

  defp check_dependency(state, nil, _, _, _), do: state

  defp check_dependency(state, dependency, function, arity, line) do
    label = if is_nil(function), do: dependency, else: "#{dependency}.#{function}/#{arity}"
    owner = package(state.path)

    rules =
      [
        native_provider_rule(state.path, dependency),
        native_completion_rule(owner, dependency),
        removed_package_rule(dependency),
        physical_graph_rule(owner, dependency),
        pure_core_rule(state.module, dependency, function)
      ]
      |> Enum.reject(&is_nil/1)

    Enum.reduce(rules, state, &add(&2, &1, line, label))
  end

  defp native_provider_rule(path, dependency) do
    if prefix?(dependency, "SystemOneSDK") and
         not String.ends_with?(path, "/fount/observe/providers/system_one.ex"),
       do: "native_provider_boundary"
  end

  defp native_completion_rule(owner, dependency) do
    if prefix?(dependency, "Inference") and owner != "fount_workshop",
      do: "native_completion_boundary"
  end

  defp removed_package_rule(dependency) do
    if dependency == "Fount" <> "Probe" or String.starts_with?(dependency, "Fount" <> "Probe."),
      do: "removed_package_dependency"
  end

  defp physical_graph_rule(owner, dependency) do
    if physical_forbidden?(owner, dependency), do: "physical_package_graph"
  end

  defp pure_core_rule(module, dependency, function) do
    if pure?(module) and pure_forbidden?(dependency, function), do: "pure_core_dependency"
  end

  defp physical_forbidden?("fount", dep),
    do:
      Enum.any?(
        ["Fount.Observe", "Fount.Intelligence", "FountWorkshop", "SystemOneSDK", "Inference"],
        &prefix?(dep, &1)
      )

  defp physical_forbidden?("fount_observe", dep),
    do: Enum.any?(["Fount.Intelligence", "FountWorkshop", "Inference"], &prefix?(dep, &1))

  defp physical_forbidden?("fount_intelligence", dep),
    do: Enum.any?(["FountWorkshop", "Inference"], &prefix?(dep, &1))

  defp physical_forbidden?(_, _), do: false

  defp pure_forbidden?(dep, function) do
    Enum.any?(@shell, &prefix?(dep, "Fount.Intelligence." <> &1)) or
      (prefix?(dep, "Fount.Observe") and dep not in Enum.map(@leaves, &("Fount.Observe." <> &1))) or
      Enum.any?(@effects, &prefix?(dep, &1)) or
      dep in Enum.map(@otp_effects, &Atom.to_string/1) or
      pure_forbidden_call?(dep, function)
  end

  defp pure_forbidden_call?(dep, function) do
    (dep == "erlang" and function in @erlang_effects) or
      (dep in ["DateTime", "NaiveDateTime", "Time", "Date"] and
         function in [:utc_now, :now, :utc_today]) or
      pure_forbidden_special_call?(dep, function)
  end

  defp pure_forbidden_special_call?(dep, function) do
    (dep == "crypto" and function == :strong_rand_bytes) or
      (dep == "Fount.ID" and function == :v4) or
      (dep == "Kernel" and function in [:apply, :spawn, :spawn_link, :send, :self, :make_ref])
  end

  defp add(state, rule, line, dependency),
    do: %{state | violations: [violation(rule, state.path, line, dependency) | state.violations]}

  defp violation(rule, path, line, dependency),
    do: %{"rule" => rule, "file" => path, "line" => line, "dependency" => dependency}

  defp physical_graph(root) do
    projects = Path.wildcard(Path.join(root, "packages/*/mix.exs"))
    packages = Enum.map(projects, &(Path.dirname(&1) |> Path.basename())) |> Enum.sort()

    errors =
      if packages == Enum.sort(@apps),
        do: [],
        else: [violation("package_set", "mix.exs", 0, inspect(packages))]

    removed = Path.join(root, "packages/fount_" <> "probe")

    errors =
      if File.exists?(removed),
        do: [
          violation(
            "removed_package_directory",
            Path.relative_to(removed, root),
            0,
            "directory must be absent, including excluded assets"
          )
          | errors
        ],
        else: errors

    Enum.reduce(projects, errors, fn project, acc ->
      owner = Path.dirname(project) |> Path.basename()
      acc ++ project_violations(project, root, owner)
    end)
  end

  defp project_violations(project, root, owner) do
    case Code.string_to_quoted(File.read!(project)) do
      {:ok, ast} ->
        {_ast, failures} =
          Macro.prewalk(ast, [], fn node, failures ->
            dependency = dependency_atom(node)
            {node, maybe_forbidden_project(failures, dependency, owner, project, root)}
          end)

        Enum.uniq(failures)

      _ ->
        [violation("project_parse", Path.relative_to(project, root), 0, "invalid project source")]
    end
  end

  defp maybe_forbidden_project(failures, dependency, owner, project, root) do
    if dependency && forbidden_project?(owner, Atom.to_string(dependency)) do
      [
        violation(
          "declared_package_dependency",
          Path.relative_to(project, root),
          0,
          Atom.to_string(dependency)
        )
        | failures
      ]
    else
      failures
    end
  end

  defp dependency_atom({:{}, _, [name | _]}) when is_atom(name), do: name
  defp dependency_atom({name, _}) when is_atom(name), do: name
  defp dependency_atom(_), do: nil

  defp forbidden_project?(owner, dependency) do
    allowed = %{
      "fount" => [],
      "fount_observe" => ["fount", "system_one_sdk"],
      "fount_intelligence" => ["fount", "fount_observe"],
      "fount_workshop" => ["fount", "fount_intelligence", "inference"]
    }

    internal = @apps ++ ["fount_" <> "probe", "system_one_sdk", "inference"]

    dependency in internal and dependency != owner and
      dependency not in Map.get(allowed, owner, [])
  end

  defp source_modules(sources, root) do
    Enum.reduce(sources, %{}, fn path, modules ->
      case Code.string_to_quoted(File.read!(path)) do
        {:ok, ast} ->
          {_ast, state} =
            Macro.traverse(ast, state(Path.relative_to(path, root)), &visit/2, &leave/2)

          Enum.reduce(
            Enum.reject(state.names, &is_nil/1),
            modules,
            &Map.put(&2, &1, Path.relative_to(path, root))
          )

        _ ->
          modules
      end
    end)
  end

  defp compiled_graph(root, expected) do
    # Mix workspace isolation can place build products outside package directories.
    # Loaded modules and all workspace build paths are considered; duplicate BEAMs
    # are inspected, not silently selected by filesystem order.
    loaded =
      Enum.flat_map(Map.keys(expected), fn name ->
        try do
          module = String.to_existing_atom("Elixir." <> name)

          case :code.which(module) do
            path when is_list(path) -> [List.to_string(path)]
            _ -> []
          end
        rescue
          ArgumentError -> []
        end
      end)

    beams =
      (Path.wildcard(Path.join(root, "**/ebin/*.beam"), match_dot: true) ++ loaded)
      |> Enum.uniq()
      |> Enum.sort()

    {errors, seen} =
      Enum.reduce(beams, {[], MapSet.new()}, fn beam, {errors, seen} ->
        inspect_beam(beam, expected, errors, seen)
      end)

    {Enum.uniq(errors),
     Map.keys(expected) |> Enum.reject(&MapSet.member?(seen, &1)) |> Enum.sort(),
     MapSet.size(seen)}
  end

  defp inspect_beam(beam, expected, errors, seen) do
    case :beam_lib.chunks(String.to_charlist(beam), [:imports, :attributes, :abstract_code]) do
      {:ok, {module, chunks}} ->
        name = module_name(module, %{})
        inspect_expected_beam(name, chunks, expected, errors, seen)

      _ ->
        {errors, seen}
    end
  end

  defp inspect_expected_beam(name, chunks, expected, errors, seen) do
    case Map.fetch(expected, name) do
      {:ok, path} ->
        state = %{module: name, aliases: %{}, violations: [], path: path}

        state =
          Enum.reduce(Keyword.get(chunks, :imports, []), state, fn {dep, fun, arity}, acc ->
            check_dependency(acc, module_name(dep, %{}), fun, arity, 0)
          end)

        # Debug forms include literal module/struct/export references absent
        # from imports. Never parse dependencies from rendered source text.
        state = scan_terms(Keyword.get(chunks, :abstract_code), state)
        state = scan_terms(Keyword.get(chunks, :attributes), state)
        {state.violations ++ errors, MapSet.put(seen, name)}

      :error ->
        {errors, seen}
    end
  end

  defp scan_terms(atom, state) when is_atom(atom) do
    dep = module_name(atom, %{})

    if String.starts_with?(Atom.to_string(atom), "Elixir.") and dep != state.module,
      do: check_dependency(state, dep, nil, nil, 0),
      else: state
  end

  defp scan_terms(tuple, state) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> scan_terms(state)

  defp scan_terms(list, state) when is_list(list), do: Enum.reduce(list, state, &scan_terms/2)
  defp scan_terms(_, state), do: state
end
