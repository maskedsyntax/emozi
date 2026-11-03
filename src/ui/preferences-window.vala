/* Preferences, laid out like Cinnamon/Xapp settings: framed lists of rows
 * with a label on the left and a control on the right. Every change applies
 * and saves immediately. */
public class Emozi.PreferencesWindow : Gtk.Window {
    private const string[] TONE_SAMPLES = { "✋", "✋🏻", "✋🏼", "✋🏽", "✋🏾", "✋🏿" };
    private const string[] TONE_NAMES = {
        "Default", "Light", "Medium-light", "Medium", "Medium-dark", "Dark"
    };

    private unowned Application app;
    private Config config;
    private UsageStore usage;

    private Gtk.Button shortcut_button;
    private Gtk.Label shortcut_error;
    private bool capturing = false;
    private bool grabbed = false;

    public PreferencesWindow (Application app, Config config, UsageStore usage) {
        Object (application: app, title: "Emozi Preferences", resizable: false,
                window_position: Gtk.WindowPosition.CENTER);
        this.app = app;
        this.config = config;
        this.usage = usage;
        icon_name = BuildConfig.APP_ID;
        get_style_context ().add_class ("emozi-preferences");

        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
        box.margin = 18;
        box.width_request = 480;

        /* --- Keyboard shortcut --- */
        box.add (heading ("Keyboard Shortcut"));
        shortcut_button = new Gtk.Button ();
        shortcut_button.valign = Gtk.Align.CENTER;
        shortcut_button.width_request = 160;
        shortcut_button.clicked.connect (() => start_capture ());
        update_shortcut_button ();
        var shortcut_list = section ();
        shortcut_list.add (row ("Open the emoji picker",
                                "Click, then press the new shortcut. Backspace restores Super+.",
                                shortcut_button));
        box.add (frame (shortcut_list));
        shortcut_error = new Gtk.Label ("");
        shortcut_error.halign = Gtk.Align.START;
        shortcut_error.wrap = true;
        shortcut_error.xalign = 0;
        shortcut_error.get_style_context ().add_class ("error");
        shortcut_error.no_show_all = true;
        box.add (shortcut_error);

        /* --- Inserting --- */
        box.add (heading ("Inserting"));
        var insert_list = section ();
        var clip = new Gtk.Switch ();
        clip.active = config.copy_to_clipboard;
        clip.notify["active"].connect (() => {
            config.copy_to_clipboard = clip.active;
            config.save ();
        });
        insert_list.add (row ("Also copy to the clipboard",
                              "Lets you paste the emoji again with Ctrl+V", clip));

        var caret = new Gtk.Switch ();
        caret.active = config.position_at_caret;
        caret.notify["active"].connect (() => {
            config.position_at_caret = caret.active;
            config.save ();
            app.ensure_caret_tracker ();
        });
        insert_list.add (row ("Open next to the text cursor",
                              "Otherwise the picker opens at the mouse pointer", caret));
        box.add (frame (insert_list));

        /* --- Emoji --- */
        box.add (heading ("Emoji"));
        var emoji_list = section ();
        emoji_list.add (row ("Default skin tone", null, tone_selector ()));

        var rows = new Gtk.SpinButton.with_range (0, 5, 1);
        rows.value = config.frequent_rows;
        rows.valign = Gtk.Align.CENTER;
        rows.value_changed.connect (() => {
            config.frequent_rows = (int) rows.value;
            config.save ();
        });
        emoji_list.add (row ("Frequently used rows", null, rows));

        var clear = new Gtk.Button.with_label ("Clear");
        clear.valign = Gtk.Align.CENTER;
        clear.clicked.connect (() => {
            usage.clear_history ();
            clear.sensitive = false;
            clear.label = "Cleared";
        });
        emoji_list.add (row ("Clear frequently used", "Skin tone choices are kept", clear));
        box.add (frame (emoji_list));

        /* --- System --- */
        box.add (heading ("System"));
        var system_list = section ();
        var login = new Gtk.Switch ();
        login.active = Autostart.is_enabled ();
        login.notify["active"].connect (() => {
            try {
                Autostart.set_enabled (login.active);
            } catch (Error e) {
                warning ("Could not change autostart: %s", e.message);
            }
        });
        system_list.add (row ("Start at login",
                              "Keeps Emozi ready in the background so it opens instantly",
                              login));
        box.add (frame (system_list));

        var footer = new Gtk.Label ("Emozi %s".printf (BuildConfig.VERSION));
        footer.get_style_context ().add_class ("dim-label");
        footer.margin_top = 6;
        box.add (footer);

        add (box);
        box.show_all ();

        focus_out_event.connect (() => {
            if (capturing) {
                stop_capture ();
            }
            return false;
        });
    }

    /* ---------- layout helpers ---------- */

    private Gtk.Label heading (string text) {
        var l = new Gtk.Label (null);
        l.set_markup ("<b>%s</b>".printf (Markup.escape_text (text)));
        l.halign = Gtk.Align.START;
        l.margin_top = 12;
        return l;
    }

    private Gtk.ListBox section () {
        var list = new Gtk.ListBox ();
        list.selection_mode = Gtk.SelectionMode.NONE;
        list.activate_on_single_click = false;
        list.set_header_func ((r, before) => {
            if (before != null && r.get_header () == null) {
                r.set_header (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            }
        });
        return list;
    }

    private Gtk.Frame frame (Gtk.Widget child) {
        var f = new Gtk.Frame (null);
        f.add (child);
        return f;
    }

    private Gtk.ListBoxRow row (string title, string? subtitle, Gtk.Widget control) {
        var hbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
        hbox.margin_start = 12;
        hbox.margin_end = 12;
        hbox.margin_top = 8;
        hbox.margin_bottom = 8;

        var labels = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
        labels.valign = Gtk.Align.CENTER;
        var t = new Gtk.Label (title);
        t.halign = Gtk.Align.START;
        labels.add (t);
        if (subtitle != null) {
            var s = new Gtk.Label (subtitle);
            s.halign = Gtk.Align.START;
            s.xalign = 0;
            s.wrap = true;
            s.max_width_chars = 40;
            s.get_style_context ().add_class ("dim-label");
            s.get_style_context ().add_class ("emozi-subtitle");
            labels.add (s);
        }
        hbox.pack_start (labels, true, true, 0);
        control.valign = Gtk.Align.CENTER;
        hbox.pack_end (control, false, false, 0);

        var r = new Gtk.ListBoxRow ();
        r.activatable = false;
        r.add (hbox);
        return r;
    }

    private Gtk.Widget tone_selector () {
        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        box.get_style_context ().add_class ("linked");
        Gtk.RadioButton? group = null;
        for (int i = 0; i < TONE_SAMPLES.length; i++) {
            var b = new Gtk.RadioButton.with_label_from_widget (group, TONE_SAMPLES[i]);
            b.set_mode (false); /* button look, no radio indicator */
            b.tooltip_text = TONE_NAMES[i];
            b.get_style_context ().add_class ("emozi-tone");
            b.active = (i == config.default_skin_tone);
            int tone = i;
            b.toggled.connect (() => {
                if (b.active) {
                    config.default_skin_tone = tone;
                    config.save ();
                }
            });
            box.add (b);
            group = b;
        }
        return box;
    }

    /* ---------- shortcut recording ---------- */

    private void update_shortcut_button () {
        shortcut_button.label = app.hotkey_registered ? app.hotkey_label : "Not set";
    }

    private void start_capture () {
        capturing = true;
        app.hotkey_suspended = true;
        shortcut_button.label = "Press a shortcut…";
        shortcut_error.hide ();

        /* Grab the keyboard actively: otherwise the desktop shell's own
         * passive grabs (Cinnamon holds Super for its menu) swallow the
         * combination before it reaches this window. */
        var seat = get_display ().get_default_seat ();
        if (seat != null && get_window () != null) {
            var status = seat.grab (get_window (), Gdk.SeatCapabilities.KEYBOARD, false,
                                    null, null, null);
            grabbed = status == Gdk.GrabStatus.SUCCESS;
            if (!grabbed) {
                debug ("Keyboard grab for shortcut recording failed: %d", (int) status);
            }
        }
    }

    private void stop_capture () {
        capturing = false;
        if (grabbed) {
            get_display ().get_default_seat ().ungrab ();
            grabbed = false;
        }
        app.hotkey_suspended = false;
        update_shortcut_button ();
    }

    private void apply_shortcut (string accel) {
        try {
            app.change_hotkey (accel);
            shortcut_error.hide ();
        } catch (Error e) {
            shortcut_error.label = e.message;
            shortcut_error.show ();
        }
        stop_capture ();
    }

    public override bool key_press_event (Gdk.EventKey ev) {
        if (!capturing) {
            if (ev.keyval == Gdk.Key.Escape &&
                (ev.state & Gtk.accelerator_get_default_mod_mask ()) == 0) {
                close ();
                return true;
            }
            return base.key_press_event (ev);
        }
        if (ev.is_modifier != 0) {
            return true;
        }
        var mods = ev.state & Gtk.accelerator_get_default_mod_mask ();

        /* Use the unshifted key so Shift+. is "<Shift>period", not "greater". */
        uint keyval = ev.keyval;
        var keymap = Gdk.Keymap.get_for_display (get_display ());
        uint base_keyval;
        if (keymap.translate_keyboard_state (ev.hardware_keycode, 0, ev.group,
                                             out base_keyval, null, null, null)) {
            keyval = base_keyval;
        }
        keyval = Gdk.keyval_to_lower (keyval);

        if (mods == 0 && keyval == Gdk.Key.Escape) {
            stop_capture ();
            return true;
        }
        if (mods == 0 && keyval == Gdk.Key.BackSpace) {
            apply_shortcut ("<Super>period");
            return true;
        }
        /* Require a real modifier, or every press of that key would be eaten. */
        var needed = Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.MOD1_MASK |
                     Gdk.ModifierType.SUPER_MASK | Gdk.ModifierType.MOD4_MASK;
        if ((mods & needed) == 0 || !Gtk.accelerator_valid (keyval, mods)) {
            shortcut_error.label = "Use a combination with Ctrl, Alt or Super.";
            shortcut_error.show ();
            return true;
        }
        /* Normalise Mod4 to Super for readable, portable accelerator names. */
        if ((mods & Gdk.ModifierType.MOD4_MASK) != 0) {
            mods = (mods & ~Gdk.ModifierType.MOD4_MASK) | Gdk.ModifierType.SUPER_MASK;
        }
        apply_shortcut (Gtk.accelerator_name (keyval, mods));
        return true;
    }
}
