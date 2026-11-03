/* User preferences, stored in ~/.config/emozi/config.ini. A plain key file
 * (rather than GSettings) keeps the app runnable uninstalled and in sandboxes. */
public class Emozi.Config : Object {
    private const string GROUP = "general";

    public string hotkey { get; set; default = "<Super>period"; }
    public bool copy_to_clipboard { get; set; default = true; }
    public bool position_at_caret { get; set; default = true; }
    /* 0 = default yellow, 1..5 = light..dark */
    public int default_skin_tone { get; set; default = 0; }
    public int frequent_rows { get; set; default = 2; }

    private string path;

    public Config (string path) {
        this.path = path;
        load ();
    }

    private void load () {
        var kf = new KeyFile ();
        try {
            kf.load_from_file (path, KeyFileFlags.NONE);
        } catch (FileError.NOENT e) {
            return;
        } catch (Error e) {
            warning ("Ignoring unreadable config %s: %s", path, e.message);
            return;
        }
        try { hotkey = kf.get_string (GROUP, "hotkey"); } catch (Error e) {}
        try { copy_to_clipboard = kf.get_boolean (GROUP, "copy-to-clipboard"); } catch (Error e) {}
        try { position_at_caret = kf.get_boolean (GROUP, "position-at-caret"); } catch (Error e) {}
        try { default_skin_tone = kf.get_integer (GROUP, "default-skin-tone").clamp (0, 5); } catch (Error e) {}
        try { frequent_rows = kf.get_integer (GROUP, "frequent-rows").clamp (0, 5); } catch (Error e) {}
    }

    public void save () {
        var kf = new KeyFile ();
        kf.set_string (GROUP, "hotkey", hotkey);
        kf.set_boolean (GROUP, "copy-to-clipboard", copy_to_clipboard);
        kf.set_boolean (GROUP, "position-at-caret", position_at_caret);
        kf.set_integer (GROUP, "default-skin-tone", default_skin_tone);
        kf.set_integer (GROUP, "frequent-rows", frequent_rows);
        try {
            DirUtils.create_with_parents (Path.get_dirname (path), 0700);
            kf.save_to_file (path);
        } catch (Error e) {
            warning ("Could not save config to %s: %s", path, e.message);
        }
    }
}
