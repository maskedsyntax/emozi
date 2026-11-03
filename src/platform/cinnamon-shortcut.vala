/* Registers the hotkey as a Cinnamon custom keyboard shortcut (the same
 * entries System Settings → Keyboard → Shortcuts → Custom creates).
 *
 * This is needed because Cinnamon keeps an active grab on Super for its menu,
 * so Super+<key> never reaches an XGrabKey from another client. Letting the
 * shell own the binding also means it shows up (and can be changed) in the
 * desktop's own settings. */
namespace Emozi.CinnamonShortcut {
    private const string LIST_SCHEMA = "org.cinnamon.desktop.keybindings";
    private const string ITEM_SCHEMA = "org.cinnamon.desktop.keybindings.custom-keybinding";
    private const string PATH_PREFIX = "/org/cinnamon/desktop/keybindings/custom-keybindings/";
    private const string NAME = "Emozi";

    public bool available () {
        string desktop = (Environment.get_variable ("XDG_CURRENT_DESKTOP") ?? "").down ();
        if (!("cinnamon" in desktop)) {
            return false;
        }
        var src = SettingsSchemaSource.get_default ();
        return src != null && src.lookup (LIST_SCHEMA, true) != null &&
               src.lookup (ITEM_SCHEMA, true) != null;
    }

    private Settings item (string id) {
        return new Settings.with_path (ITEM_SCHEMA, PATH_PREFIX + id + "/");
    }

    /* Create or update our entry so `accel` runs `command`. Throws if another
     * custom shortcut already uses the same keys. */
    public void register (string accel, string command) throws Error {
        uint key;
        Gdk.ModifierType mods;
        Gtk.accelerator_parse (accel, out key, out mods);
        if (key == 0) {
            throw new IOError.INVALID_ARGUMENT ("“%s” is not a valid shortcut", accel);
        }

        var list = new Settings (LIST_SCHEMA);
        string[] ids = list.get_strv ("custom-list");
        string? mine = null;

        foreach (unowned string id in ids) {
            var s = item (id);
            if (s.get_string ("name") == NAME) {
                mine = id;
                continue;
            }
            foreach (unowned string b in s.get_strv ("binding")) {
                uint k2;
                Gdk.ModifierType m2;
                Gtk.accelerator_parse (b, out k2, out m2);
                if (k2 == key && m2 == mods) {
                    throw new IOError.EXISTS ("%s is already used by the custom shortcut “%s”",
                                              Gtk.accelerator_get_label (key, mods),
                                              s.get_string ("name"));
                }
            }
        }

        bool added = false;
        if (mine == null) {
            for (int n = 0; mine == null; n++) {
                string candidate = "custom%d".printf (n);
                if (!(candidate in ids)) {
                    mine = candidate;
                }
            }
            added = true;
        }

        var s = item (mine);
        bool changed = added || s.get_string ("command") != command ||
                       strv_differs (s.get_strv ("binding"), { accel });
        if (!changed) {
            return;
        }

        s.delay ();
        s.set_string ("name", NAME);
        s.set_string ("command", command);
        s.set_strv ("binding", { accel });
        s.apply ();

        /* Cinnamon only reloads custom shortcuts when the list changes, so
         * rewrite it (adding our id if new). */
        string[] new_ids = {};
        foreach (unowned string id in ids) {
            if (id != mine) {
                new_ids += id;
            }
        }
        if (!added) {
            list.set_strv ("custom-list", new_ids);
            Settings.sync ();
        }
        new_ids += mine;
        list.set_strv ("custom-list", new_ids);
        Settings.sync ();
    }

    private bool strv_differs (string[] a, string[] b) {
        if (a.length != b.length) {
            return true;
        }
        for (int i = 0; i < a.length; i++) {
            if (a[i] != b[i]) {
                return true;
            }
        }
        return false;
    }
}
