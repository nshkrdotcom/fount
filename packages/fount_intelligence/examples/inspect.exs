model =
  Fount.Screenplay.new(
    scenes: [
      %{heading: "INT. HALL - NIGHT", elements: [%{type: :action, text: "Mara pockets the key."}]}
    ]
  )

params = %{"selection" => %{"whole_screenplay" => true}, "include_summaries" => false}
{:ok, report} = Fount.Intelligence.run(model, "inventory", params)
IO.puts(Jason.encode!(Fount.Intelligence.Reporting.Report.to_map(report), pretty: true))
