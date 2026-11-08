# Brief 5: documentation

Workers 5a to 5d.

Same bar as comments: concise, present-tense, current state. Read the Phase 1 reports first.

1. **`AGENTS.md`** (5a): says little, all true.
2. **`architecture`** (5a): domain table, the cross-domain interfaces (the index and each `interfaces/` file), dependency graph,
   conventions and the files beside `SKILL.md`. The domain count agrees everywhere it is stated:

   ```bash
   ls -d scenes/*/ | wc -l    # the real number (seventeen)
   grep -rniE "[a-z]+ (isolated )?domains" AGENTS.md .skillshare/skills/architecture/SKILL.md
   ```

3. **Each `domain-<name>` skill and side file** (5b–5c): the read-through of `audit` step 3 against the code, flagging every
   untrue or unneeded passage. Its interface pointers name the right `architecture` interfaces. A mechanism or method
   removed in Brief 1a/1b goes from the skills too (a deleted accessor still listed as a sub-domain interface is the usual
   case). Files and tests named still exist (tests live under `tests/<domain>/`).
4. **Code comments** (5d): the comment rules are `audit` step 4. Whole-codebase scripts:

   ```bash
   # Undocumented functions and members, and ticket numbers in game comments (scenes/): the lint rules.
   tools/lint.sh --rule=doc_comments,comment_ticket_refs

   # Undocumented non-lifecycle functions in tools/ scripts, which the rules leave out.
   find tools -name '*.gd' -not -path 'tools/coverage/tests/fixtures/*' | while IFS= read -r f; do
     awk 'prev !~ /^[[:space:]]*##/ && prev !~ /^[[:space:]]*@/ && $0 ~ /^[[:space:]]*(static )?func / {
       l=$0; sub(/\(.*/,"",l); gsub(/^[[:space:]]*/,"",l); print FILENAME":"NR": "l } { prev=$0 }' "$f"
   done | grep -vE 'func _(ready|process|physics_process|draw|init|input|exit_tree|notification|unhandled_input|enter_tree|integrate_forces)\b'

   # Files with no `##` header in their first lines.
   find scenes -name '*.gd' | while IFS= read -r f; do head -3 "$f" | grep -q '^##' || echo "$f"; done

   # History / speculation sweep (noisy by design: judge each hit).
   grep -rniE '\b(renamed|moved to|moved from|used to|formerly|previously|no longer|in future|for now|todo|fixme|hack|legacy|deprecated)\b' scenes --include='*.gd'
   ```

