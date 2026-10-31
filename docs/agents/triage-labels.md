# Triage Labels

The skills speak of five canonical triage roles; this file maps them to this tracker's label strings.

| Label in mattpocock/skills | Label in our tracker | Meaning                                  |
| -------------------------- | -------------------- | ---------------------------------------- |
| `needs-triage`             | `needs-triage`       | Maintainer needs to evaluate this issue  |
| `needs-info`               | `needs-info`         | Waiting on reporter for more information |
| `ready-for-agent`          | `ready-for-agent`    | Fully specified, ready for an AFK agent  |
| `ready-for-human`          | `ready-for-human`    | Requires human implementation            |
| `wontfix`                  | `wontfix`            | Will not be actioned                     |

A skill's role (e.g. "the AFK-ready triage label") is the label string in this table. An issue with no state label counts as
`needs-triage`.

## Category roles

| Role in mattpocock/skills | In our tracker |
| ------------------------- | -------------- |
| `bug`                     | `bug`          |
| `enhancement`             | no label: any issue without `bug` or `spike` (`ai`, `harness`, `refactor`, `assets`, … are kinds of enhancement `ticket` routes on) |

`spike` is a third kind, an investigation that plans tickets. `ticket` routes each kind to its file (`ticket` (`spike.md`)).
Topic labels (`physics`, `navigation`, …) are not categories. Rejected enhancements are recorded in
`.out-of-scope/<concept>.md`.
