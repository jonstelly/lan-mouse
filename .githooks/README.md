This repository includes a local git hooks directory `.githooks/` with a `pre-commit` script
that enforces formatting, lints, and tests before allowing a commit.

To enable the hook locally (recommended):

1. Make the hook executable:

   chmod +x .githooks/pre-commit

2. Point git to the hooks directory (one-time per clone):

   git config core.hooksPath .githooks

The `pre-commit` script will run the following checks:

- `cargo fmt --all -- --check` — ensures code is rustfmt-formatted
- `cargo clippy --all-features --all-targets -- -D warnings` — matches CI lint policy
- `cargo test --workspace --all-features` — ensures tests pass

If you prefer to keep using the default `.git/hooks` directory, copy the script there and make it executable.

