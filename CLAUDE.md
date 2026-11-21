# easy-box-packer

Ruby gem, a 3D bin-packing engine. One file, `easy-box-packer.rb`, with specs in
`easy-box-packer_spec.rb`. Ruby >= 2.7, no runtime dependencies.

## Before any task: read the knowledge base

The project knowledge base is [alChaCC/easy-box-packer-kb](https://github.com/alChaCC/easy-box-packer-kb):
read its README.md, dependencies.md and projects/easy-box-packer.md first.
After any change, open or update a KB PR (see its CONTRIBUTING.md) and write
`KB: alChaCC/easy-box-packer-kb#N` (or `KB: n/a (reason)`) in the code PR body.
Write to the KB only from your own git worktree of it, never in someone else's checkout.
Changing anything the API relies on (public methods, options, result shapes, `unpacked`
reasons)? Run the full-system e2e in [alChaCC/easy-box-packer-qa](https://github.com/alChaCC/easy-box-packer-qa)
(`bin/system-e2e` with this branch) before merging.

## Boundaries

- Packing only: placements, constraints, loading order, box choice. No accounts, no
  shipping or DIM-weight cost.
- Results must always be valid: no overlaps, inside the box, constraints and weight
  limits kept, and every item either placed or reported (`errors` / `unpacked`).
- `time_limit` is an upper bound (since 0.5.0). Keep it that way: anything new that can
  run long must check the deadline, and the fallback must stay valid.
- New `unpacked` reasons or result keys are additions for API clients; renaming or
  removing them is breaking. Tell the API side either way.

## Commands

| what | command |
|---|---|
| specs | `bundle install && bundle exec rspec easy-box-packer_spec.rb` |
| CI | `.github/workflows/ci.yml`: rspec on Ruby 2.7 and 3.4 |

Run the specs on both 2.7 and 3.4 before opening a PR (2.7 has no endless `def`,
no `it` / `_1` block params).

## Release

1. In a PR: bump `s.version` in `easy-box-packer.gemspec` and add a Changelog entry
   to the README.
2. After the merge: `gem build easy-box-packer.gemspec && gem push easy-box-packer-X.Y.Z.gem`.
   **Only the maintainer runs `gem push`** (it needs their RubyGems key and MFA). Never
   push a gem from an agent session; ask.
