defmodule FountWorkshop.LiveExample do
  @moduledoc false
  alias Fount.LiveArtifacts, as: A
  alias FountWorkshop.{Session, Store, Candidate}

  @modes ~w(bridge alternatives propagate sequence_routes character_workspace grouped_notes pass_all recover_scene investigate)
  def modes, do: @modes

  def run(mode, output, options \\ []) do
    A.run(mode, output, fn directory ->
      repo = Fount.CLI.Support.connect() |> A.require!()
      {root, _} = A.fixture()
      key = "writer-#{mode}-#{Fount.ID.v4()}"
      Fount.Persistence.create(repo, key, root) |> A.require!()
      clients = FountProbe.Launcher.clients() |> A.require!()

      services = %{
        store: Store.new(repo),
        inference: clients.inference,
        jev: clients.system_one,
        renderer: FountWorkshop.Export.PDF
      }

      budget = FountProbe.Budget.new(max_inference_calls: 40, max_jev_states: 1500)

      opts = [
        budget: budget,
        max_inference_calls: 40,
        max_jev_states: 1500,
        max_context_bytes: 100_000,
        output_dir: directory,
        render: mode == "sequence_routes",
        pdf: true,
        actor: "live-example-writer"
      ]

      {base, sessions, details} = execute(mode, root, key, services, opts)

      packets =
        Enum.map(sessions, fn session ->
          FountWorkshop.Review.export(
            session["id"],
            Path.join(directory, session["id"]),
            services,
            pdf: true
          )
          |> A.require!()
        end)

      head = Fount.Persistence.load(repo, key) |> A.require!()
      if head.revision.id != base.revision.id, do: raise("Generation moved the accepted head")

      decision =
        if options[:accept_demo],
          do: accept_demo(sessions, base, services),
          else: %{"accepted" => false}

      result = %{
        "key" => key,
        "screenplay_id" => base.id,
        "base_revision_id" => base.revision.id,
        "session_ids" => Enum.map(sessions, & &1["id"]),
        "packets" => packets,
        "details" => details,
        "decision" => decision,
        "spent" => FountProbe.Budget.snapshot(budget)
      }

      A.write!(directory, "fixture-bindings.json", %{
        "scenes" =>
          Enum.map(
            base.ir.scenes,
            &%{"id" => &1.id, "heading" => Fount.Query.node(base, &1.heading_id).text}
          ),
        "cast" => Map.values(base.cast)
      })

      result
    end)
  end

  defp execute("bridge", root, _key, services, opts) do
    [left, right | _] = root.ir.scenes

    request =
      req(
        root,
        "develop",
        "Write a short playable bridge from the marina office to the equipment shed. Give Mara an active choice; retain both neighboring scenes exactly.",
        scenes([left, right]),
        %{
          "placement" => %{
            "kind" => "between_scenes",
            "after_scene_id" => left.id,
            "before_scene_id" => right.id
          }
        }
      )

    session = start(root, request, services, opts)
    [first | _] = candidates(session, services)

    changed =
      Enum.find(first["screenplay"].ir.elements, fn e ->
        e.type == :action and is_nil(Fount.Query.node(root, e.id))
      end) || raise("Bridge contains no new action")

    edit = %{
      "kind" => "replace_text",
      "target" => %{"kind" => "element", "id" => changed.id},
      "value" => changed.text <> " Mara makes herself go first."
    }

    edited = Candidate.edit(first["id"], [edit], services, opts) |> A.require!()
    reopened = Store.call(services.store, :candidate, [edited["id"]]) |> A.require!()

    if Fount.Query.node(reopened["screenplay"], changed.id).text != edit["value"],
      do: raise("Writer edit did not reopen exactly")

    {root, [session],
     %{"edited_candidate_id" => edited["id"], "retained_neighbors" => [left.id, right.id]}}
  end

  defp execute("alternatives", root, _key, services, opts) do
    first = hd(root.ir.scenes)

    request =
      req(
        root,
        "alternatives",
        "Write two genuinely different dramatic approaches to this opening. Revise multiple exchanges and actions in each; give each independently meaningful selectable groups, with dependencies where needed. One approach uses evasion through practical tasks; the other forces a costly admission without revealing the ledger forgery yet.",
        scenes([first]),
        %{}
      )

    session = start(root, request, services, opts)
    [a, b | _] = candidates(session, services)

    changed = fn c ->
      Enum.filter(c["screenplay"].ir.elements, fn e ->
        old = Fount.Query.node(root, e.id)
        old && e.type in [:action, :dialogue] && e.text != old.text
      end)
    end

    from_a = List.first(changed.(a))

    from_b =
      Enum.find(changed.(b), &(&1.id != (from_a && from_a.id)))

    pick = fn candidate, changed_element ->
      if changed_element do
        %{
          "candidate_id" => candidate["id"],
          "ranges" => [
            %{"source" => target(changed_element), "target" => target(changed_element)}
          ]
        }
      else
        group =
          Enum.find(candidate["change_groups"], fn group ->
            Enum.any?(group["operations"], &(&1["kind"] == "insert_elements"))
          end) || raise("Alternative has no selectable passage")

        %{"candidate_id" => candidate["id"], "group_ids" => [group["id"]]}
      end
    end

    selection = %{
      "picks" => [
        pick.(a, from_a),
        pick.(b, from_b)
      ],
      "join" => %{
        "instruction" =>
          "Write connective action or replies so these writer-selected passages form one scene. Keep both selected passages byte-identical; add connective writing rather than replacing their words.",
        "selection" => scenes([first])
      }
    }

    combined = Candidate.combine([a["id"], b["id"]], selection, services, opts) |> A.require!()

    A.write!(opts[:output_dir], "combination-request.json", %{
      "candidate_ids" => [a["id"], b["id"]],
      "selection" => selection
    })

    audition =
      FountWorkshop.Audition.build(combined["id"], scenes([first]), services, opts)
      |> A.require!()

    {root, [session],
     %{
       "combined_candidate_id" => combined["id"],
       "audition" => audition,
       "source_candidate_ids" => [a["id"], b["id"]]
     }}
  end

  defp execute("propagate", root, _key, services, opts) do
    records = Enum.at(root.ir.scenes, 2)
    queue = Enum.at(root.ir.scenes, 5)

    request =
      req(
        root,
        "propagate",
        "Delay Dan's explicit ledger confession from the records room to the ferry queue. Rewrite Mara's earlier accusation and reactions that require that admission, preserve her independent reason to reach the accountant, retain the key handoff and service-gate use. Put primary change and dependent repairs in explicit groups.",
        whole(),
        %{
          "change" => "Delay the ledger confession from scene 3 to scene 6",
          "destination" => %{"kind" => "replace_range", "scene_ids" => [queue.id]},
          "repair_scope" => whole()
        }
      )

    request =
      Map.put(request, "constraints", [
        key_pin(root),
        semantic(root, "not-yet-confessed", records.id, false),
        semantic(root, "confessed-in-queue", queue.id, true)
      ])

    session = start(root, request, services, opts)

    traces =
      Enum.map(
        [%{"id" => "base", "screenplay" => root} | candidates(session, services)],
        fn candidate ->
          model = candidate["screenplay"]

          points = [
            FountProbe.LiveExample.end_point(model, records.id),
            FountProbe.LiveExample.end_point(model, queue.id)
          ]

          report =
            FountProbe.run(
              model,
              "knowledge_trace",
              %{
                "proposition" => "Dan has explicitly confessed to forging the ledger.",
                "subjects" => [
                  %{"kind" => "reader"},
                  %{"kind" => "audience"},
                  %{"kind" => "character", "character_id" => cast(model, "MARA")}
                ],
                "points" => points,
                "access_mode" => "evidence"
              },
              Store.clients(services),
              opts
            )
            |> A.require!()

          Session.save_reports([report], session["id"], services, [model]) |> A.require!()

          A.write!(
            opts[:output_dir],
            candidate["id"] <> ".knowledge.json",
            FountProbe.Report.to_map(report)
          )

          %{
            "candidate_id" => candidate["id"],
            "report_id" => report.id,
            "status" => report.status
          }
        end
      )

    {root, [session], %{"before_after_knowledge" => traces}}
  end

  defp execute("sequence_routes", root, _key, services, opts) do
    selected = Enum.take(root.ir.scenes, 5)

    request =
      req(
        root,
        "sequence",
        "Rebuild the first five scenes as three. One route turns the closing office into a confrontation with an immediate practical consequence; the other makes progress through a joint task that changes allegiance. These must be different causal routes, not the same abridgment. Preserve the key transfer, ferry motive and specific dry joke. Render both; report measured pages even if there is no saving.",
        scenes(selected),
        %{
          "target_scene_count" => 3,
          "page_reduction" => 1,
          "entry_requirements" => ["Mara needs the original ledger."],
          "exit_requirements" => ["They must use the service gate to reach the accountant."]
        }
      )

    joke =
      Enum.find(
        root.ir.elements,
        &String.contains?(&1.text, "We bill by the berth, not by altitude.")
      )

    request = Map.put(request, "constraints", [key_pin(root), pin(joke, "keep-dry-joke")])
    session = start(root, request, services, opts)

    {root, [session],
     %{
       "selected_scene_ids" => Enum.map(selected, & &1.id),
       "requested_scene_count" => 3,
       "page_measurements" =>
         "See each actual layout_compare report; zero or negative savings are retained."
     }}
  end

  defp execute("character_workspace", root, _key, services, opts) do
    id = cast(root, "DAN")

    request =
      req(
        root,
        "character",
        "Rewrite Dan's choices and responses across the draft. Let practical competence gradually stop serving as evasion. Repair Mara's replies and action where the change requires it, without verbal tics, a changed ferry motive, or moving his original confession.",
        whole(),
        %{
          "character_id" => id,
          "direction" => "Competence as evasion gives way to accepting exposure.",
          "change_agency" => true
        }
      )

    request = Map.put(request, "constraints", [key_pin(root)])
    {root, [start(root, request, services, opts)], %{"character_id" => id}}
  end

  defp execute("grouped_notes", root, key, services, opts) do
    first = hd(root.ir.scenes)
    ramp = Enum.at(root.ir.scenes, 3)

    notes = [
      note(
        root,
        first,
        "local",
        "Make Dan's evasion force Mara to do something rather than just supply a quip."
      ),
      note(
        root,
        ramp,
        "sequence",
        "Let helping Dan remain in conflict with resenting him; coordinate the ramp scene with the later gate choice."
      ),
      note(root, ramp, "conflict", "Do not soften Mara's distrust into forgiveness.")
    ]

    ops = Enum.map(notes, &%{"kind" => "put_authored_item", "value" => &1})
    {base, _} = apply_and_save(root, key, ops, services)

    request =
      req(
        base,
        "notes",
        "Address the local and sequence notes in coordinated selectable groups. Keep conflicting interpretations visible. Do not claim every note resolved when only one group is selected.",
        whole(),
        %{"note_ids" => Enum.map(notes, & &1["id"])}
      )

    session = start(base, request, services, opts)
    [candidate | _] = candidates(session, services)
    [group | _] = candidate["change_groups"]
    selected = Candidate.select(candidate["id"], [group["id"]], services, opts) |> A.require!()

    {base, [session],
     %{
       "selected_candidate_id" => selected["id"],
       "selected_group_id" => group["id"],
       "note_statuses" => selected["screenplay"].authored_items
     }}
  end

  defp execute("pass_all", root, _key, services, opts) do
    sessions =
      Enum.map(~w(dialogue_subtext action_visual brevity dry_comedy tension custom), fn profile ->
        request =
          req(
            root,
            "pass",
            "Apply this creative lens selectively to the opening without changing the story facts. Preserve intentional expressive turns; do not polish everything into one rhythm.",
            scenes([hd(root.ir.scenes)]),
            %{
              "profile" => profile,
              "direction" =>
                "Make Mara's practical objective collide with Dan's effort to delay her."
            }
          )
          |> Map.put("alternatives", 1)

        start(root, request, services, opts)
      end)

    {root, sessions,
     %{"profiles" => ~w(dialogue_subtext action_visual brevity dry_comedy tension custom)}}
  end

  defp execute("recover_scene", root, key, services, opts) do
    lost = Enum.at(root.ir.scenes, 1)

    {base, _} =
      apply_and_save(
        root,
        key,
        [%{"kind" => "delete_scene", "target" => %{"kind" => "scene", "id" => lost.id}}],
        services
      )

    destination = %{"kind" => "after_scene", "after_scene_id" => hd(base.ir.scenes).id}

    sessions =
      Enum.map([false, true], fn adapt ->
        request =
          req(
            base,
            "recover",
            "Recover the equipment-shed scene from the inspected earlier revision. For the adapted version, let Mara take the initiative in obtaining the key while retaining the later gate payoff.",
            whole(),
            %{
              "source_revision_id" => root.revision.id,
              "source_targets" => [%{"kind" => "scene", "id" => lost.id}],
              "destination" => destination,
              "adapt" => adapt
            }
          )
          |> Map.put("alternatives", 1)

        start(base, request, services, opts)
      end)

    {base, sessions,
     %{"historical_revision_id" => root.revision.id, "deleted_scene_id" => lost.id}}
  end

  defp execute("investigate", root, _key, services, opts) do
    request =
      req(
        root,
        "investigate",
        "Why does the opening feel like a question-and-answer exercise instead of a conflict between people? Test competing explanations against exact pages. Produce three meaningfully different strategies and write two remedies.",
        scenes([hd(root.ir.scenes)]),
        %{
          "concern" =>
            "The opening exchanges information but the characters' tactics do not change.",
          "write_fixes" => true
        }
      )

    {root, [start(root, request, services, opts)], %{}}
  end

  defp execute(_, _, _, _, _), do: raise(ArgumentError, "Unknown real Workshop mode")

  defp start(model, request, services, opts) do
    case Session.start(model, request, services, opts) do
      {:ok, session} ->
        session

      {:error, _, session} = error ->
        _ =
          FountWorkshop.Review.export(
            session["id"],
            Path.join(opts[:output_dir], session["id"]),
            services
          )

        A.require!(error)

      error ->
        A.require!(error)
    end
  end

  defp candidates(session, services),
    do:
      Store.call(services.store, :candidates_for_session, [session["id"]])
      |> Enum.map(&Store.normalize/1)

  defp req(model, workflow, instruction, selection, options),
    do: %{
      "version" => 1,
      "workflow" => workflow,
      "mode" => "revise",
      "base_revision_id" => model.revision.id,
      "instruction" => instruction,
      "selection" => selection,
      "constraints" => [],
      "alternatives" => 2,
      "options" => options
    }

  defp scenes(values), do: %{"targets" => Enum.map(values, &%{"kind" => "scene", "id" => &1.id})}
  defp whole, do: %{"whole_screenplay" => true}
  defp target(e), do: %{"kind" => "element", "id" => e.id}

  defp cast(model, name),
    do:
      Enum.find_value(model.cast, fn {id, c} -> if c.display_name == name, do: id end) ||
        raise("Fixture cast missing")

  defp pin(e, id),
    do: %{
      "id" => id,
      "target" => target(e),
      "kind" => "pin_text",
      "spec" => %{"text" => e.text},
      "severity" => "required",
      "source" => "writer"
    }

  defp key_pin(root),
    do:
      root.ir.elements
      |> Enum.find(&String.contains?(&1.text, "He puts the key in her hand. She pockets it."))
      |> pin("keep-key-transfer")

  defp semantic(root, id, scene_id, expected),
    do: %{
      "id" => id,
      "kind" => "semantic",
      "target" => %{"kind" => "screenplay", "id" => root.id},
      "spec" => %{
        "proposition" => "Dan has explicitly confessed to forging the ledger.",
        "projection" => "page_reader",
        "at" => %{"kind" => "scene", "id" => scene_id},
        "expected" => expected
      },
      "severity" => "required",
      "source" => "writer"
    }

  defp note(_root, scene, id, instruction),
    do: %{
      "id" => Fount.ID.v4(),
      "namespace" => "writer",
      "kind" => "note",
      "target" => %{"kind" => "scene", "id" => scene.id},
      "value" => %{"label" => id, "instruction" => instruction},
      "dependencies" => [],
      "status" => "active",
      "provenance" => %{"source" => "writer"}
    }

  defp apply_and_save(root, key, ops, services) do
    {:ok, edited, changes} = Fount.Screenplay.apply(root, ops)

    saved =
      Fount.Persistence.save_edit(services.store.repo, key, edited,
        expected_revision: root.revision.id,
        actor: "live-example-writer",
        operations: changes.operations
      )
      |> A.require!()

    {saved, changes}
  end

  defp accept_demo(sessions, base, services) do
    [first_session | _] = sessions

    candidate =
      candidates(first_session, services)
      |> Enum.find(fn c ->
        Enum.all?(
          c["provenance"]["checks"] || [],
          &(&1["severity"] != "required" or &1["status"] == "pass")
        )
      end)

    if is_nil(candidate),
      do:
        throw(
          {:live_failure,
           %{"reason" => "No candidate passes required checks; demo does not invent overrides."}}
        )

    review = %{
      "candidate_id" => candidate["id"],
      "content_hash" => candidate["screenplay"].revision.content_hash,
      "actor" => "live-example-explicit-approval",
      "report_ids" => candidate["provenance"]["report_ids"],
      "overrides" => []
    }

    accepted =
      FountWorkshop.Acceptance.accept(candidate["id"], base.revision.id, review, services)
      |> A.require!()

    %{
      "accepted" => true,
      "candidate_id" => candidate["id"],
      "revision_id" => accepted.revision.id
    }
  end
end
