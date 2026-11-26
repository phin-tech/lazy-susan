# Integrating another app with Lazy Susan

Another app (Cubicle, say) can add a group of its own commands to Lazy Susan, and can fill groups at run time with
live data such as its workspaces. Nothing here needs Lazy Susan's code: an app writes JSON and opens a URL.

## Is Lazy Susan installed?

Its bundle identifier is `tech.phin.LazySusan`:

```swift
let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "tech.phin.LazySusan") != nil
```

## Items

Everything uses the same item format as Lazy Susan's own `config.json`:

```jsonc
{ "key": "g", "type": "command", "label": "Go to workspace", "value": "/path/to/cubicle go {input}" }
{ "key": "d", "type": "url", "label": "Docs", "value": "https://example.com" }
{ "key": "w", "type": "group", "label": "Windows", "actions": [ /* items */ ] }
{ "key": "s", "type": "group", "label": "Switch to", "source": "/path/to/cubicle leader go" }
```

- `type` is `command`, `url`, `application`, `folder` or `group`.
- `key` is one character. `label` is what menus show; `iconPath` (optional) is an image or an app's path.
- **Prompted actions.** `{input}` in a command or URL makes Lazy Susan ask for text first. A command receives it as
  `"$LAZYSUSAN_INPUT"`, never spliced into the command line, so it is safe in any shell; a URL gets it
  percent-encoded.
- Commands run with the user's login shell (`$SHELL -c`, which may be fish), non-interactively, so `PATH` may not
  include the user's own folders. **Use absolute paths**, double-quoted if they can contain spaces.

## Dynamic groups

A group with a `source` command (and no `actions`) is filled each time the user enters it. Lazy Susan runs the command
and reads its standard output as JSON: either an array of items or `{ "actions": [ ... ] }`.

- It must finish within 3 seconds and exit 0. Otherwise the group shows as failed, with the first line of standard
  error (the last line, since a login shell such as fish may print its own startup errors first).
- Items may leave out `key`. Lazy Susan then gives them `1`–`9`, `0`, then `a`–`z`, skipping keys already used.
- Items may be groups, including other dynamic groups.
- A dynamic group shows its items as soon as it is entered, even when the user has the cheatsheet on a delay: its
  items change, so nobody knows them by heart. Any group can set `"showImmediately": true` (or `false` to turn this
  off for a dynamic group).

Example output of `cubicle leader go`:

```json
[
  { "key": "1", "type": "command", "label": "Mail", "value": "\"/Applications/Cubicle.app/Contents/Helpers/cubicle\" go 1" },
  { "key": "2", "type": "command", "label": "Code", "value": "\"/Applications/Cubicle.app/Contents/Helpers/cubicle\" go 2" }
]
```

## Installing a group

1. Write one group item, with a `key`, to a JSON file. Leave it in place: Lazy Susan reads it when it handles the URL,
   which can be a moment later if Lazy Susan has to launch first.
2. Open `lazysusan://install?file=<the file's absolute path, percent-encoded>`.

Lazy Susan asks the user before changing anything, then adds the group to the top level of their config. If the key
is taken, the user can replace what's there or cancel. Installing again later replaces the old copy, so an app can
offer "Update" with the same call.
