/* Resident single-instance application. The first `emozi` process stays in
 * the background with the picker pre-built, so opening it is instant; later
 * invocations (`emozi --toggle`, a desktop-launcher click) just forward their
 * command line to it over D-Bus. */
public class Emozi.Application : Gtk.Application {
    private EmojiStore store;
    private UsageStore usage;
    private Config config;
    private PickerWindow? picker = null;
    private CaretTracker? caret = null;
    private bool is_x11 = false;

    private ulong previous_window = 0;
    private uint regrab_source = 0;
    private bool hotkey_ok = false;
    private int64 dismissed_at = 0;

    public Application () {
        Object (application_id: BuildConfig.APP_ID,
                flags: ApplicationFlags.HANDLES_COMMAND_LINE);

        add_main_option ("toggle", 't', OptionFlags.NONE, OptionArg.NONE,
                         "Show the picker, or hide it if visible (default)", null);
        add_main_option ("show", 's', OptionFlags.NONE, OptionArg.NONE,
                         "Show the picker", null);
        add_main_option ("background", 'b', OptionFlags.NONE, OptionArg.NONE,
                         "Start in the background without showing the picker", null);
        add_main_option ("quit", 'q', OptionFlags.NONE, OptionArg.NONE,
                         "Quit the running instance", null);
        add_main_option ("version", 'v', OptionFlags.NONE, OptionArg.NONE,
                         "Print the version and exit", null);
    }

    public override int handle_local_options (VariantDict options) {
        if (options.contains ("version")) {
            print ("emozi %s\n", BuildConfig.VERSION);
            return 0;
        }
        return -1;
    }

    public override void startup () {
        base.startup ();
        hold (); /* stay resident */

        is_x11 = X11.is_active ();

        var css = new Gtk.CssProvider ();
        css.load_from_resource ("/io/github/maskedsyntax/Emozi/style.css");
        Gtk.StyleContext.add_provider_for_screen (Gdk.Screen.get_default (), css,
                                                  Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);

        config = new Config (Path.build_filename (Environment.get_user_config_dir (),
                                                  "emozi", "config.ini"));
        usage = new UsageStore (Path.build_filename (Environment.get_user_data_dir (),
                                                     "emozi", "usage.ini"));
        try {
            store = new EmojiStore.from_resource ();
        } catch (Error e) {
            critical ("Could not load emoji data: %s", e.message);
            quit ();
            return;
        }

        picker = new PickerWindow (this, store, usage, config);
        picker.emoji_chosen.connect (on_emoji_chosen);
        picker.dismissed.connect (on_dismissed);

        int64 t0 = get_monotonic_time ();
        int hidden = Coverage.compute (store, picker.get_grid_pango_context (),
                                       picker.get_emoji_font ());
        debug ("Font coverage check: %d hidden, %.0f ms", hidden,
               (get_monotonic_time () - t0) / 1000.0);
        picker.prepare (); /* rebuild sections with the coverage applied */

        if (config.position_at_caret) {
            caret = new CaretTracker ();
        }

        setup_hotkey ();
    }

    public override int command_line (ApplicationCommandLine cmd) {
        var opts = cmd.get_options_dict ();
        if (opts.contains ("quit")) {
            quit ();
            return 0;
        }
        if (picker == null) {
            return 1;
        }
        if (opts.contains ("background")) {
            if (hotkey_ok) {
                uint key;
                Gdk.ModifierType mods;
                Gtk.accelerator_parse (config.hotkey, out key, out mods);
                cmd.print ("Emozi is running in the background. Press %s to open the picker.\n",
                           Gtk.accelerator_get_label (key, mods));
            } else {
                cmd.print ("Emozi is running, but the shortcut could not be set up (see the " +
                           "warning above). Use `emozi --toggle` to open the picker.\n");
            }
            return 0;
        }
        if (opts.contains ("show")) {
            show_picker (Gdk.CURRENT_TIME);
        } else {
            toggle (Gdk.CURRENT_TIME);
        }
        return 0;
    }

    public override void activate () {
        toggle (Gdk.CURRENT_TIME);
    }

    /* ---------- hotkey ---------- */

    /* Absolute command that toggles this binary's picker. */
    private static string toggle_command () {
        string exe;
        try {
            exe = FileUtils.read_link ("/proc/self/exe");
        } catch (Error e) {
            exe = "emozi";
        }
        return Shell.quote (exe) + " --toggle";
    }

    private void setup_hotkey () {
        /* Cinnamon swallows Super+<key> for its menu, so let the shell own
         * the binding there; it then runs `emozi --toggle`. */
        if (CinnamonShortcut.available ()) {
            try {
                CinnamonShortcut.register (config.hotkey, toggle_command ());
                debug ("Hotkey %s registered as a Cinnamon custom shortcut", config.hotkey);
                hotkey_ok = true;
                return;
            } catch (Error e) {
                warning ("Could not register the Cinnamon shortcut: %s", e.message);
                return;
            }
        }

        if (!is_x11) {
            message ("Not an X11 session: bind a shortcut to `emozi --toggle` in your " +
                     "desktop's keyboard settings.");
            return;
        }
        try {
            X11.hotkey_grab (config.hotkey, on_hotkey);
            debug ("Hotkey %s registered", config.hotkey);
            hotkey_ok = true;
        } catch (Error e) {
            warning ("%s. Set another \"hotkey\" in %s, or bind `emozi --toggle` in " +
                     "your desktop's keyboard settings.", e.message,
                     Path.build_filename (Environment.get_user_config_dir (), "emozi", "config.ini"));
            return;
        }

        /* Keycodes change with the keyboard layout; re-grab (debounced). Our
         * own synthetic typing also triggers this, which is harmless. */
        Gdk.Keymap.get_for_display (Gdk.Display.get_default ()).keys_changed.connect (() => {
            if (regrab_source != 0) {
                Source.remove (regrab_source);
            }
            regrab_source = Timeout.add (500, () => {
                regrab_source = 0;
                try {
                    X11.hotkey_grab (config.hotkey, on_hotkey);
                } catch (Error e) {
                    warning ("Re-grabbing hotkey failed: %s", e.message);
                }
                return Source.REMOVE;
            });
        });
    }

    private void on_hotkey (uint32 timestamp) {
        debug ("Hotkey pressed (time %u)", timestamp);
        toggle (timestamp);
    }

    /* ---------- show / hide ---------- */

    private void toggle (uint32 timestamp) {
        if (picker == null) {
            return;
        }
        if (picker.visible) {
            picker.dismiss ();
            return;
        }
        /* Pressing the shortcut makes the shell grab the keyboard, so the
         * picker loses focus and closes itself just before our toggle
         * arrives. That press meant "close", so don't reopen. */
        if (get_monotonic_time () - dismissed_at < 400 * 1000) {
            return;
        }
        show_picker (timestamp);
    }

    private void show_picker (uint32 timestamp) {
        if (picker.visible) {
            picker.present_with_time (timestamp);
            return;
        }
        previous_window = is_x11 ? X11.get_active_window () : 0;

        picker.prepare ();
        int x, y;
        Positioner.compute (caret, config.position_at_caret && is_x11, previous_window,
                            PickerWindow.WIDTH, PickerWindow.HEIGHT, out x, out y);
        picker.move (x, y);

        if (caret != null) {
            caret.paused = true; /* ignore our own focus events */
        }
        if (timestamp == Gdk.CURRENT_TIME && is_x11) {
            picker.realize ();
            timestamp = X11.get_server_time (picker.get_window ());
        }
        picker.present_with_time (timestamp);
    }

    private void on_dismissed () {
        dismissed_at = get_monotonic_time ();
        if (caret != null) {
            caret.paused = false;
        }
    }

    /* ---------- insertion ---------- */

    private void on_emoji_chosen (Emoji emoji, string text) {
        usage.record (emoji, text);
        picker.dismiss ();

        if (config.copy_to_clipboard || !is_x11) {
            var cb = Gtk.Clipboard.get_default (Gdk.Display.get_default ());
            cb.set_text (text, -1);
            cb.store ();
        }
        if (!is_x11) {
            return; /* clipboard only on Wayland, for now */
        }
        insert_into_previous.begin (text);
    }

    /* Give focus back to the window the user was typing in, wait until the
     * WM confirms it, then type the emoji there. */
    private async void insert_into_previous (string text) {
        ulong target = previous_window;
        if (target != 0 && X11.get_active_window () != target) {
            X11.activate_window (target, Gdk.CURRENT_TIME);
        }
        for (int waited = 0; waited < 500; waited += 10) {
            if (target == 0 || X11.get_active_window () == target) {
                break;
            }
            Timeout.add (10, insert_into_previous.callback);
            yield;
        }
        /* let the target process its FocusIn before keys arrive */
        Timeout.add (40, insert_into_previous.callback);
        yield;

        try {
            X11.type_text (text);
        } catch (Error e) {
            warning ("Typing failed (%s); the emoji is on the clipboard.", e.message);
        }
    }
}
