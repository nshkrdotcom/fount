# Called after dependency retrieval, without starting the Phoenix application.
Application.ensure_all_started(:postgrex)
Logger.configure(level: :critical)

case FountWeb.DevDatabase.resolve(System.get_env("FOUNT_DATABASE_URL")) do
  {:ok, url, description} ->
    [path] = System.argv()
    File.write!(path, url)
    IO.puts("PostgreSQL connection verified: #{description}")

  {:error, message} ->
    IO.puts(:stderr, message)
    System.halt(1)
end
