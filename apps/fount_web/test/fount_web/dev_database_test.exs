defmodule FountWeb.DevDatabaseTest do
  use ExUnit.Case, async: true
  alias FountWeb.DevDatabase

  defp resolve(env, sockets, ports, probe) do
    DevDatabase.resolve(nil, env: env, sockets: sockets, ports: ports, probe: probe)
  end

  test "explicit URL is preserved and never falls back after authentication failure" do
    url = "ecto://writer:private@remote:5544/story?ssl=true"

    assert {:error, message} =
             DevDatabase.resolve(url,
               probe: fn opts ->
                 assert opts[:hostname] == "remote"
                 assert opts[:port] == 5544
                 {:error, "authentication unavailable"}
               end
             )

    assert message =~ "No fallback"
    refute message =~ "private"
    assert {:ok, ^url, _} = DevDatabase.resolve(url, probe: fn _ -> {:ok, :server} end)
  end

  test "invalid explicit URLs never expose credentials" do
    assert {:error, message} = DevDatabase.resolve("ecto://private-secret")
    refute message =~ "private-secret"
    assert message =~ "invalid PostgreSQL URL"
  end

  for port <- [5432, 5433, 5549] do
    test "discovers local socket on #{port} with the operating-system role" do
      port = unquote(port)

      probe = fn opts ->
        if opts[:socket_dir] == "/tmp" and opts[:username] == "writer" and opts[:port] == port,
          do: {:ok, :one_server},
          else: {:error, "unavailable"}
      end

      assert {:ok, url, description} = resolve(%{"USER" => "writer"}, [{"/tmp", port}], [], probe)
      assert url =~ ":#{port}/fount_dev?socket_dir="
      assert description =~ "local socket"
    end
  end

  test "configured PG connection takes priority over discovery" do
    env = %{
      "USER" => "writer",
      "PGHOST" => "localhost",
      "PGPORT" => "5544",
      "PGUSER" => "app",
      "PGPASSWORD" => "secret"
    }

    assert {:ok, url, description} =
             resolve(env, [], [], fn opts ->
               assert opts[:port] == 5544
               assert opts[:username] == "app"
               assert opts[:password] == "secret"
               {:ok, :configured}
             end)

    assert url =~ ":5544/"
    refute description =~ "secret"
  end

  test "failed local PG defaults can discover a verified peer-authenticated connection" do
    env = %{
      "USER" => "writer",
      "PGHOST" => "localhost",
      "PGPORT" => "5432",
      "PGUSER" => "postgres"
    }

    probe = fn opts ->
      if opts[:socket_dir] && opts[:username] == "writer",
        do: {:ok, :peer},
        else: {:error, "unavailable"}
    end

    assert {:ok, url, _} = resolve(env, [{"/tmp", 5433}], [5433], probe)
    assert url =~ "writer@localhost:5433/"
  end

  test "remote PG connection never falls back to a local database" do
    env = %{"USER" => "writer", "PGHOST" => "remote", "PGPORT" => "5433"}

    assert {:error, message} =
             resolve(env, [{"/tmp", 5433}], [], fn opts ->
               assert opts[:hostname] == "remote"
               {:error, "unavailable"}
             end)

    assert message =~ "No local fallback"
  end

  test "multiple authenticated servers are ambiguous" do
    assert {:error, message} =
             resolve(%{"USER" => "writer"}, [{"/tmp", 5432}, {"/tmp", 5433}], [], fn opts ->
               if opts[:socket_dir], do: {:ok, opts[:port]}, else: {:error, "unavailable"}
             end)

    assert message =~ "Multiple usable"
    assert message =~ "5432"
    assert message =~ "5433"
  end

  test "socket aliases and TCP connections to the same server are deduplicated" do
    assert {:ok, url, _} =
             resolve(
               %{"USER" => "writer"},
               [{"/run/postgresql", 5433}, {"/var/run/postgresql", 5433}],
               [],
               fn _ -> {:ok, :same_server} end
             )

    assert url =~ "socket_dir="
  end

  test "absence and authentication failures produce actionable errors without secrets" do
    assert {:error, message} =
             resolve(%{"USER" => "writer", "PGPASSWORD" => "private"}, [], [], fn _ ->
               {:error, "unavailable"}
             end)

    assert message =~ "--database-url"
    assert message =~ "does not create roles"
    refute message =~ "private"
  end

  test "invalid PGPORT is rejected before connection" do
    for value <- ["no", "0", "65536", "5433oops"] do
      assert {:error, message} =
               resolve(%{"PGPORT" => value}, [], [], fn _ -> flunk("must not connect") end)

      assert message =~ "PGPORT"
    end
  end

  test "generated connection URL safely encodes credentials and socket paths" do
    url =
      DevDatabase.url(
        username: "writer:name",
        password: "a@b:c /?",
        socket_dir: "/tmp/a b",
        port: 5433
      )

    opts = Ecto.Repo.Supervisor.parse_url(url)
    assert opts[:username] == "writer:name"
    assert opts[:password] == "a@b:c /?"
    assert opts[:socket_dir] == "/tmp/a b"
    assert opts[:port] == 5433
  end

  test "discovery reads hidden socket names and excludes lock files" do
    dir = Path.join(System.tmp_dir!(), "fount-sockets-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    File.write!(Path.join(dir, ".s.PGSQL.5433"), "")
    File.write!(Path.join(dir, ".s.PGSQL.5433.lock"), "")
    File.write!(Path.join(dir, "unrelated"), "")
    assert DevDatabase.sockets(%{}, [dir]) == [{dir, 5433}]
  end

  test "a valid target connection does not require maintenance database access" do
    assert {:ok, :identity} =
             DevDatabase.check_databases([database: "project"], fn _, database ->
               assert database == "project"
               {:ok, :identity, true}
             end)
  end

  test "maintenance connection can verify creation only when the target is absent" do
    assert {:ok, :identity} =
             DevDatabase.check_databases([database: "new"], fn _, database ->
               case database do
                 "new" -> {:error, "unavailable"}
                 "postgres" -> {:ok, :identity, false}
               end
             end)
  end

  test "maintenance access does not conceal denial to an existing target database" do
    assert {:error, "target inaccessible"} =
             DevDatabase.check_databases([database: "existing"], fn _, database ->
               case database do
                 "existing" -> {:error, "target inaccessible"}
                 "postgres" -> {:ok, :identity, true}
               end
             end)
  end
end
