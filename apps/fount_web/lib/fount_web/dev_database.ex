defmodule FountWeb.DevDatabase do
  @moduledoc "Read-only connection discovery for the development launcher."

  @socket_dirs ["/var/run/postgresql", "/run/postgresql", "/tmp"]

  def resolve(url, opts \\ []) do
    env = Keyword.get(opts, :env, System.get_env())
    probe = Keyword.get(opts, :probe, &probe/1)

    if is_binary(url) and url != "" do
      with {:ok, connection} <- parse(url),
           {:ok, _identity} <- probe.(connection) do
        {:ok, url, describe(connection)}
      else
        {:error, reason} ->
          {:error, "Explicit database connection failed: #{reason}. No fallback was attempted."}
      end
    else
      discover(env, probe, opts)
    end
  end

  defp discover(env, probe, opts) do
    with {:ok, port} <- port_number(env["PGPORT"] || "5432") do
      check_preferred(env, probe, opts, port)
    end
  end

  defp check_preferred(env, probe, opts, port) do
    host = env["PGHOST"] || "localhost"
    user = env["PGUSER"] || env["USER"] || System.get_env("USER")
    preferred = connection(host, port, user, env["PGPASSWORD"])
    configured? = Enum.any?(~w(PGHOST PGPORT PGUSER PGPASSWORD), &Map.has_key?(env, &1))
    result = if configured?, do: probe.(preferred), else: {:error, "not configured"}

    case result do
      {:ok, _} -> success(preferred)
      {:error, reason} -> discover_local(host, env, probe, opts, port, reason)
    end
  end

  defp discover_local(host, env, probe, opts, port, reason) do
    if local_host?(host) do
      sockets = Keyword.get_lazy(opts, :sockets, fn -> sockets(env) end)
      ports = Keyword.get_lazy(opts, :ports, &cluster_ports/0)
      choose(candidates(env, sockets, ports, port), probe)
    else
      {:error, "Configured PGHOST connection failed: #{reason}. No local fallback was attempted."}
    end
  end

  def candidates(env, sockets, ports, preferred_port) do
    user = env["PGUSER"] || env["USER"]
    os_user = env["USER"]
    password = env["PGPASSWORD"]

    socket_candidates =
      for {dir, port} <- sockets,
          username <- Enum.uniq([os_user, user]),
          is_binary(username) and username != "" do
        connection(dir, port, username, if(username == user, do: password))
      end

    tcp_candidates =
      for port <- Enum.uniq([preferred_port, 5432 | ports] ++ Enum.map(sockets, &elem(&1, 1))),
          username <- Enum.uniq([user, os_user]),
          is_binary(username) and username != "" do
        connection("localhost", port, username, if(username == user, do: password))
      end

    Enum.uniq(socket_candidates ++ tcp_candidates)
  end

  def choose(candidates, probe) do
    found =
      Enum.reduce(candidates, [], fn connection, acc ->
        case probe.(connection) do
          {:ok, identity} -> [{identity, connection} | acc]
          {:error, _} -> acc
        end
      end)
      |> Enum.reverse()
      |> Enum.uniq_by(&elem(&1, 0))

    case found do
      [{_, connection}] ->
        success(connection)

      [] ->
        {:error,
         "No usable local PostgreSQL connection found. Start PostgreSQL and configure FOUNT_DATABASE_URL or use --database-url. Authentication and database-creation permission must be supplied by your environment; the launcher does not create roles or change passwords."}

      _ ->
        choices = Enum.map_join(found, "; ", fn {_, connection} -> describe(connection) end)

        {:error,
         "Multiple usable PostgreSQL servers found (#{choices}). Select one with --database-url or FOUNT_DATABASE_URL."}
    end
  end

  defp success(connection), do: {:ok, url(connection), describe(connection)}

  defp connection(host, port, username, password) do
    base = [port: port, username: username, password: password, database: "fount_dev"]

    if String.starts_with?(host, "/"),
      do: Keyword.put(base, :socket_dir, host),
      else: Keyword.put(base, :hostname, host)
  end

  defp local_host?(host),
    do: host in ["localhost", "127.0.0.1", "::1"] or String.starts_with?(host, "/")

  defp port_number(value) do
    case Integer.parse(value) do
      {port, ""} when port > 0 and port <= 65_535 -> {:ok, port}
      _ -> {:error, "PGPORT must be an integer between 1 and 65535"}
    end
  end

  defp parse(url) do
    uri = URI.parse(url)
    if uri.scheme not in ~w(ecto postgres postgresql), do: raise(ArgumentError)
    {:ok, Keyword.put_new(Ecto.Repo.Supervisor.parse_url(url), :port, 5432)}
  rescue
    _ -> {:error, "invalid PostgreSQL URL (credentials have been omitted)"}
  end

  def url(connection) do
    username = URI.encode(connection[:username] || "", &URI.char_unreserved?/1)
    password = connection[:password]

    credentials =
      username <>
        if(is_binary(password),
          do: ":" <> URI.encode(password, &URI.char_unreserved?/1),
          else: ""
        )

    host = connection[:hostname] || "localhost"
    host = if String.contains?(host, ":"), do: "[#{host}]", else: host

    socket =
      if connection[:socket_dir],
        do: "?" <> URI.encode_query(%{"socket_dir" => connection[:socket_dir]}),
        else: ""

    "ecto://#{credentials}@#{host}:#{connection[:port]}/fount_dev#{socket}"
  end

  def describe(connection) do
    endpoint =
      if connection[:socket_dir], do: "local socket", else: connection[:hostname] || "localhost"

    "#{endpoint}:#{connection[:port] || 5432}, user #{connection[:username] || "environment"}"
  end

  def sockets(env, dirs \\ @socket_dirs) do
    extra = if String.starts_with?(env["PGHOST"] || "", "/"), do: [env["PGHOST"]], else: []

    for dir <- Enum.uniq(extra ++ dirs),
        {:ok, names} <- [File.ls(dir)],
        name <- names,
        String.starts_with?(name, ".s.PGSQL."),
        {:ok, port} <- [port_number(String.replace_prefix(name, ".s.PGSQL.", ""))] do
      {dir, port}
    end
  end

  defp cluster_ports do
    if System.find_executable("pg_lsclusters") do
      read_cluster_ports(System.cmd("pg_lsclusters", ["--no-header"], stderr_to_stdout: true))
    else
      []
    end
  end

  defp read_cluster_ports({output, 0}) do
    for line <- String.split(output, "\n"),
        [_version, _name, port, status | _] <- [String.split(line)],
        String.starts_with?(status, "online"),
        {:ok, port} <- [port_number(port)],
        do: port
  end

  defp read_cluster_ports(_), do: []

  def probe(connection), do: check_databases(connection, &probe_database/2)

  def check_databases(connection, attempt) do
    case attempt.(connection, connection[:database]) do
      {:ok, identity, _exists?} -> {:ok, identity}
      {:error, _} = original_error -> check_maintenance(connection, attempt, original_error)
    end
  end

  defp check_maintenance(connection, attempt, original_error) do
    case attempt.(connection, "postgres") do
      {:ok, identity, false} -> {:ok, identity}
      {:ok, _identity, true} -> original_error
      {:error, _} = error -> error
    end
  end

  defp probe_database(connection, database) do
    # One attempt, bounded time, no supervisor or reconnect loop. Never log credentials.
    previous = Process.flag(:trap_exit, true)

    options =
      connection
      |> Keyword.put(:database, database)
      |> Keyword.merge(
        backoff_type: :stop,
        timeout: 1_500,
        connect_timeout: 1_500,
        queue_target: 100
      )

    result =
      case Postgrex.start_link(options) do
        {:ok, pid} ->
          try do
            case Postgrex.query(
                   pid,
                   "SELECT pg_postmaster_start_time()::text, rolsuper OR rolcreatedb OR EXISTS (SELECT 1 FROM pg_database WHERE datname = $1), EXISTS (SELECT 1 FROM pg_database WHERE datname = $1) FROM pg_roles WHERE rolname = current_user",
                   [connection[:database]],
                   timeout: 2_000
                 ) do
              {:ok, %{rows: [[identity, true, exists?]]}} ->
                {:ok, {connection[:port] || 5432, identity}, exists?}

              {:ok, _} ->
                {:error, "role cannot create the development database"}

              {:error, _} ->
                {:error, "connection or authentication unavailable"}
            end
          catch
            :exit, _ -> {:error, "connection or authentication unavailable"}
          after
            if Process.alive?(pid), do: GenServer.stop(pid, :normal)

            receive do
              {:EXIT, ^pid, _} -> :ok
            after
              0 -> :ok
            end
          end

        {:error, _} ->
          {:error, "connection or authentication unavailable"}
      end

    Process.flag(:trap_exit, previous)
    result
  end
end
