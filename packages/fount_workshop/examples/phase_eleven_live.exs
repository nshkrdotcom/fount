# Phase-11 Workshop live generation QC. Explicit opt-in and one-scene/one-candidate only.
unless System.get_env("FOUNT_PHASE11_WORKSHOP_LIVE") == "1" do
  raise "Phase-11 Workshop live QC is disabled. Set FOUNT_PHASE11_WORKSHOP_LIVE=1 after authorizing the generation call."
end

out =
  System.get_env("FOUNT_PHASE11_WORKSHOP_OUT") ||
    Path.expand("examples/_output/phase_eleven_qc")

result = FountWorkshop.LiveExample.run("phase_eleven_qc", out, accept_demo: false)
result = Fount.LiveArtifacts.require!(result)

if get_in(result, ["decision", "accepted"]) != false,
  do: raise("Phase-11 live QC must not accept a generated candidate")

IO.puts(Jason.encode!(result, pretty: true))
