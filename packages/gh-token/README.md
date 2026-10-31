# gh-token

Keep GitHub CLI access and refresh tokens in one age-encrypted file.
The `programs.aldur.secrets` module sets the age identities and recipients.

Import a refresh token once:

```sh
passage show github/gh-refresh | gh-token init
```

Use `gh-token init` without a pipe for a hidden prompt. Import does not
contact GitHub. The first use exchanges the imported refresh token.

In Fish, use `ghs` with the usual GitHub CLI arguments:

```fish
ghs pr list
```

`ghs` sets `GH_TOKEN` only for that command. It keeps `gh` completions and
returns the command's exit status. Other shells can use:

```sh
(token=$(gh-token) && GH_TOKEN="$token" gh pr list)
```

Each use decrypts the credentials and can require a YubiKey touch or PIN.
A valid access token is reused. Near expiry, the helper exchanges the
refresh token and saves the new pair encrypted before it prints the access
token. A lock prevents concurrent refreshes. The helper writes only ciphertext
to disk. Plaintext credentials use pipes and process memory.

State is stored in `$XDG_STATE_HOME/gh-token/credentials.age`, or
`~/.local/state/gh-token/credentials.age`. The default directory is preserved
across home resets. This mutable file replaces Passage as the token source
after import. Do not import the old Passage token again after a refresh.

For a new login, remove the state file and import a new refresh token.
Requests are not retried. A lost refresh response can require a new login.
If file replacement fails, the error gives the path to an encrypted recovery
file. Move that file to `credentials.age` before the next use.

Standalone installations need `GH_TOKEN_IDENTITIES_FILE` and
`GH_TOKEN_RECIPIENTS_FILE`. These variables contain public file paths.

The public OAuth credentials belong to the
[GitHub CLI app](https://github.com/cli/cli/blob/trunk/internal/authflow/flow.go).
Use refresh tokens issued to that app. See
[GitHub's refresh flow](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps#refreshing-an-access-token-with-a-refresh-token).
