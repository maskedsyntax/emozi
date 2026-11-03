/* "Start at login", done the way desktop session managers expect: the
 * system entry in /etc/xdg/autostart is overridden by a same-named file in
 * ~/.config/autostart (this is also what Startup Applications writes). */
namespace Emozi.Autostart {
    private string file_name () {
        return BuildConfig.APP_ID + ".desktop";
    }

    private string user_path () {
        return Path.build_filename (Environment.get_user_config_dir (), "autostart", file_name ());
    }

    private bool entry_enabled (string path) {
        var kf = new KeyFile ();
        try {
            kf.load_from_file (path, KeyFileFlags.NONE);
        } catch (Error e) {
            return false;
        }
        const string G = "Desktop Entry";
        try {
            if (kf.get_boolean (G, "Hidden")) {
                return false;
            }
        } catch (Error e) {}
        try {
            if (!kf.get_boolean (G, "X-GNOME-Autostart-enabled")) {
                return false;
            }
        } catch (Error e) {}
        return true;
    }

    public bool is_enabled () {
        if (FileUtils.test (user_path (), FileTest.EXISTS)) {
            return entry_enabled (user_path ());
        }
        foreach (unowned string dir in Environment.get_system_config_dirs ()) {
            string p = Path.build_filename (dir, "autostart", file_name ());
            if (FileUtils.test (p, FileTest.EXISTS)) {
                return entry_enabled (p);
            }
        }
        return false;
    }

    public void set_enabled (bool enabled) throws Error {
        var kf = new KeyFile ();
        const string G = "Desktop Entry";
        kf.set_string (G, "Type", "Application");
        kf.set_string (G, "Name", "Emozi");
        kf.set_string (G, "Comment", "Emoji picker");
        kf.set_string (G, "Exec", Shell.quote (Application.executable_path ()) + " --background");
        kf.set_string (G, "Icon", BuildConfig.APP_ID);
        kf.set_boolean (G, "Terminal", false);
        kf.set_boolean (G, "NoDisplay", true);
        kf.set_boolean (G, "Hidden", !enabled);
        kf.set_boolean (G, "X-GNOME-Autostart-enabled", enabled);
        DirUtils.create_with_parents (Path.get_dirname (user_path ()), 0755);
        kf.save_to_file (user_path ());
    }
}
