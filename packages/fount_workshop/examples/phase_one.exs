Code.require_file("support/phase_one_demo.exs", __DIR__)
{opts, rest, invalid} = OptionParser.parse(System.argv(), strict: [out: :string, decision: :string, pdf: :boolean])
if rest != [] or invalid != [], do: raise("usage: mix run examples/phase_one.exs --out DIR --decision accept|reject [--pdf]")
decision = case Keyword.get(opts, :decision, "reject") do
  "accept" -> :accept
  "reject" -> :reject
  _ -> raise("decision must be accept or reject")
end
{:ok, _pid} = Fount.Repo.start_link(url: System.fetch_env!("FOUNT_DATABASE_URL"), pool_size: 2)
{:ok, manifest} = FountWorkshop.Examples.PhaseOneDemo.run(Fount.Repo,
  out: Keyword.get(opts, :out, "examples/_output/phase_one"), decision: decision, pdf: Keyword.get(opts, :pdf, false))
IO.puts(Jason.encode!(manifest, pretty: true))
