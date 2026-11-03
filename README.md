# Emozi

A fast, native-looking emoji picker for Linux, written in Vala with GTK 3,
that works like the macOS one: press **Super+.**, start typing, and press
**Enter** to type the emoji into the app you were using.

- All of Unicode 17.0's emoji (3,944), filtered at runtime to what your
  fonts can draw, so you never see empty boxes
- Opens under the text caret (via AT-SPI) or at the mouse pointer
- Search by name, keyword or `:shortcode:`; accent and case insensitive
- Frequently Used, and remembers the skin tone you picked for each emoji
- Follows your GTK theme (Mint-Y, Adwaita, Arc… in light or dark)

## Build

```sh
sudo apt install valac meson libgtk-3-dev libxtst-dev libatspi2.0-dev python3
meson setup build
ninja -C build
meson test -C build
```

Try it without installing:

```sh
./build/src/emozi --background   # start the resident service (grabs Super+.)
./build/src/emozi --toggle       # or press Super+.
./build/src/emozi --quit
```

### Install

```sh
meson setup build --prefix=/usr/local --buildtype=release   # or --reconfigure
ninja -C build
sudo ninja -C build install
emozi --background        # start now; afterwards it starts at every login
```

This installs `/usr/local/bin/emozi`, a menu entry, and an autostart entry
in `/etc/xdg/autostart`. You can turn autostart off in *Startup
Applications*. On Cinnamon, the shortcut is registered as a custom
keyboard shortcut named "Emozi". If the service isn't running, pressing the
shortcut starts it and opens the picker.

To remove Emozi, run `sudo ninja -C build uninstall`, then delete the
"Emozi" entry under Keyboard → Shortcuts → Custom.

## Keys

| Key | Action |
| --- | --- |
| type | search |
| ←↑→↓, Tab, PgUp/PgDn | move the selection |
| Enter | insert the selected emoji |
| Shift+Enter, Menu, right-click, long-press | choose a skin tone |
| Esc | clear the search, then close |

## Configuration

`~/.config/emozi/config.ini`:

```ini
[general]
hotkey=<Super>period          # GTK accelerator syntax, e.g. <Control><Super>space
copy-to-clipboard=true        # also put the emoji on the clipboard
position-at-caret=true
default-skin-tone=0           # 0 = yellow, 1–5 = light…dark
frequent-rows=2
```

Restart the service (`emozi --quit; emozi --background`) after editing.

## How insertion works

On X11, Emozi gives focus back to the previous window and types the emoji
with XTest. It temporarily maps spare keycodes to the emoji's Unicode
keysyms, which is the same approach xdotool uses. Terminals work too. On
Wayland the emoji is copied to the clipboard for now; native Wayland support
is planned.

## Updating emoji data

Replace the files in `data/unicode/` with newer ones from
`unicode.org/Public/<ver>/emoji/emoji-test.txt` and CLDR
`common/annotations{,Derived}/en.xml`, then rebuild. The generator fails the
build if the counts don't add up.
