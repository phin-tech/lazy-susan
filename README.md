# Lazy Susan

Every shortcut you need, one spin away: a keyboard launcher for macOS where nested key sequences open apps, URLs, folders and commands.

Lazy Susan is a fork of [Leader Key](https://github.com/mikker/LeaderKey) by [Mikkel Malmberg](https://github.com/mikker) (MIT licensed; see `LICENSE`). Nearly everything here is his work. If you like the idea, look at his newer launcher, [Tuna](https://tunaformac.com), which has Leader Key built in.

What Lazy Susan adds:

- **Which Key theme**: a Spacemacs-style panel along the bottom of the screen that lists every key at the current level in columns, with groups marked `+Name` and the keys pressed so far in a status line.
- **Radial theme**: a pie menu in the middle of the screen. At most 8 keys per ring, two rings, then a list. A trail shows the groups you've entered. It follows Settings ▸ Advanced ▸ Cheatsheet: *Always* opens the wheel straight away, *After …* keeps it a small dot until you hesitate for that long (so once you know your keys you never see it), and *Never* keeps it a dot. `?` opens it at any time.

Pick either in Settings ▸ General ▸ Theme.

- **Prompted actions**: put `{input}` in a command or URL and Lazy Susan asks for text before running it. Type, press ↩ to run, or esc to go back to the menu; ⌥⌫ deletes a word, ⌘⌫ clears, ⌘V pastes. For example, with [Cubicle](https://github.com/phin-tech/cubicle):

  | Key | Type | Value |
  | --- | --- | --- |
  | `r` | Command | `cubicle rename {input}` |
  | `g` | Command | `cubicle go {input}` |
  | `t` | Command | `cubicle rename-tab {input}` |
  | `s` | URL | `https://duckduckgo.com/?q={input}` |

  Commands get the text as `$LAZYSUSAN_INPUT` (`{input}` becomes `"$LAZYSUSAN_INPUT"`), so quotes, `;` and `$(…)` in what you type are never run as shell code, in sh, zsh, bash or fish. URLs get it percent-encoded.

### Coming from Leader Key

Lazy Susan keeps its own settings and config, so it can run beside Leader Key. To bring your shortcuts over, copy `~/Library/Application Support/Leader Key/config.json` to `~/Library/Application Support/Lazy Susan/config.json`, or choose your existing folder under Settings ▸ Advanced ▸ Config directory. The URL scheme is `lazysusan://` in place of `leaderkey://`.

## Using Lazy Susan

**The \*faster than your launcher\* launcher**

A riff on [Raycast](https://www.raycast.com), [@mxstbr's multi-key Karabiner setup](https://www.youtube.com/watch?v=m5MDv9qwhU8&t=540s), and Vim's `<leader>` key.

## Install

Download Lazy Susan from [apps.phin.tech](https://apps.phin.tech) or the Phin Tech Store.

### Post-Install setup
- Open the settings menu with the menu bar icon <img width="17" alt="Screenshot 2025-05-21 at 1 58 46 PM" src="https://github.com/user-attachments/assets/7ba2cd99-dbd1-4b23-a35b-c5579e797321" />
- Choose your [`leader`](#what-do-i-set-as-my-leader-key) (`Shortcut` that will open the app) 

  <img width="213" alt="Screenshot 2025-05-21 at 2 01 56 PM" src="https://github.com/user-attachments/assets/5e486a9a-ee1c-4ac7-a2d9-f4d0a46eb734" />
- Add your [shortcuts](#example-shortcuts) to the `Config` settings

## Why Lazy Susan?

### Problems with traditional launchers:

1. Typing the name of the thing can be slow and give unpredictable results.
2. Global shortcuts have limited combinations.
3. Lazy Susan offers predictable, nested shortcuts -- like combos in a fighting game.

### Example Shortcuts:

- <kbd>leader</kbd><kbd>o</kbd><kbd>m</kbd> → Launch Messages (`open messages`)
- <kbd>leader</kbd><kbd>m</kbd><kbd>m</kbd> → Mute audio (`media mute`)
- <kbd>leader</kbd><kbd>w</kbd><kbd>m</kbd> → Maximize current window (`window maximize`)

## URL Scheme

Lazy Susan supports URL scheme automation for integration with tools like Alfred, Raycast, shell scripts, and more.

### Available URL Schemes

#### Configuration Management
```bash
# Reload configuration from disk
open "lazysusan://config-reload"

# Show config.json in Finder
open "lazysusan://config-reveal"
```

#### Window Control
```bash
# Show Lazy Susan's window
open "lazysusan://activate"

# Hide Lazy Susan's window
open "lazysusan://hide"

# Clear navigation state (return to root)
open "lazysusan://reset"
```

#### Settings & Info
```bash
# Open settings window
open "lazysusan://settings"

# Show about dialog
open "lazysusan://about"
```

#### Navigation
```bash
# Navigate through keys and execute actions
open "lazysusan://navigate?keys=a,b,c"

# Navigate without executing (preview mode)
open "lazysusan://navigate?keys=a,b,c&execute=false"
```

### Example Use Cases

- **Alfred/Raycast workflows**: Trigger Lazy Susan shortcuts programmatically
- **Shell scripts**: Automate configuration reloads after editing config.json
- **Keyboard maestro**: Chain Lazy Susan actions with other automations
- **External triggers**: Open specific action sequences from other applications

## FAQ

#### What do I set as my leader key?

Any key can be your leader key, but **only modifiers will not work**.

**Examples:**

- <kbd>F12</kbd>
- <kbd>⌘ + space</kbd>
- <kbd>⌘⌥ + space</kbd>
- <kbd>⌘⌥⌃⇧ + L</kbd> (hyper key)

**Advanced examples:**

Using [Karabiner](https://karabiner-elements.pqrs.org/) you can do more fancy things like:

- <kbd>right ⌘ + left ⌘</kbd> at once (bound to <kbd>F12</kbd>) my personal favorite
- <kbd>caps lock</kbd> (bound to <kbd>hyper</kbd> when held, <kbd>F12</kbd> when pressed)

See [@mikker's config](https://github.com/mikker/LeaderKey.app/wiki/@mikker's-config) in the Leader Key wiki for an akimbo cmds example.

#### I disabled the menubar item, how can I get Lazy Susan back?

Activate Lazy Susan, then <kbd>cmd + ,</kbd>.

#### Command action is failing with "Command not found"

You need to make sure your shell environment is correctly set up for non-interactive mode, and exports the `PATH` variable.

**For zsh** make sure you have your `PATH` variable exported in `~/.zshenv`

**For bash** make sure you have your `PATH` variable exported in `~/.bash_profile`


## License

MIT. See `LICENSE`: the original copyright is Mikkel Malmberg's.
