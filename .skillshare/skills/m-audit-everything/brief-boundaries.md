# Briefs 2, 3, 4: redundancy, isolation, splits

Workers 2, 3 and 4.

## Brief 2 — Redundancy (worker 2)

Duplication that means one fix must be made twice:
- **Same logic twice** (geometry, a physics query, a clamp): say which owns it and which calls across.
- **Two paths, one job:** a fallback converged with its primary; a special case the general case covers.
- **Pass-through indirection:** a forwarding wrapper, a parameter threaded through layers; a module's private helpers
  shouldn't take what the module owns as an argument.
- **Dead branches:** a condition that can't be false, a null guard on something guaranteed.

## Brief 3 — Domain isolation, repo-wide (worker 3)

`audit` step 1, for every boundary. Start from `python3 -I tools/audit_scan.py deps` (every `unit -> unit` edge with its
crossing symbols, `scenes/ai/<sub>/` its own unit, `main.gd` skipped as the composition root, then the `preload` / `load` and
`ext_resource` matrices). Check:

1. **Every edge is published** in `architecture`'s interfaces or graph. If not: reroute, or promote to a small façade /
   contract method **and add it to `architecture`**.
2. **Direction:** no cycles; Physics, Navigation, Art, Audio and World-Gen are leaves.
3. **Duck-typed calls** (AI and UI call the character and controller as plain `Node`) are published too:

   ```bash
   grep -rhoE "\b(character|_character|other|body|victim|node)\.(\w+)" scenes/ai --include='*.gd' | sed -E 's/^[^.]+\.//' | sort | uniq -c | sort -rn
   grep -rhoE "\b(_character|_controller|_player|npc)\.(\w+)" scenes/ui scenes/general --include='*.gd' | sed -E 's/^[^.]+\.//' | sort | uniq -c | sort -rn
   ```

   An unlisted member called across domains: publish it. A `has_method("x")` used as a type test changes meaning on a
   rename: recommend an explicit marker.
4. **Leanest connection:** `get_node("GoalController")` couples to layout; a duck-typed probe to behaviour.
5. **No private reach-in:**

   ```bash
   grep -rnE "[a-zA-Z)\]]\._[a-z][a-zA-Z0-9_]*" scenes --include='*.gd' | grep -vE "^\S+:[0-9]+:\s*#|\bself\._"
   ```

   Within a domain, a draw helper reading its owner's private (`wall_visuals` → `_wall._seg_impacts`) is the
   control/animate/draw convention; across domains it is a violation.

The same test applies between the AI sub-domains (perception, decision, behaviour, debug): the `deps` footer reports
sub-domain `class_name` edges; also read how `behavior.gd` reaches `_perception` and how the debug overlays reach the
controller.

## Brief 4 — Is a domain due a split? (worker 4)

Numbers first: the Step 0 table, plus each domain over ~1,500 lines or ~15 files grouped by topic. Signals: a folder far
larger than its siblings or one file carrying most of it; a file over ~700 lines; a header needing "and also …"; clusters
that don't talk to each other (two or three outside files mentioning a cluster = a cheap cut); repeated cross-domain glue.
Judge coupling and responsibility, not size (`worldgen/` is large but cohesive). A good seam owns the state it mutates (a
back-reference into the parent's privates is the wrong seam). A new script changing load order can add exit-time leak lines
to the load check (`godot-run`, `--strict-exit`).

**A split comes with its detail:** the sub-domain's skill content becomes a side file of the parent skill
(`domain-<parent>/<sub>.md`, pointed to from the parent's `SKILL.md`), the parent keeps an overview plus a one-line pointer
per child, and `architecture`'s table names it.

Per recommendation: sub-folder name(s), files that move, what it owns, the one interface the rest keeps (`class_name`
survives a move; count the `preload("res://…")` paths, docs and `ext_resource`s to edit). Rank by seam cleanliness. **Never
invent a split.**

