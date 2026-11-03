/* Row of category buttons at the bottom of the picker (macOS-style). */
public class Emozi.CategoryBar : Gtk.Box {
    public signal void category_selected (int section_id);

    private Gtk.Button[] buttons = {};
    private int[] ids = {};

    public CategoryBar () {
        Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 0, homogeneous: true);
        get_style_context ().add_class ("emozi-category-bar");

        add_category (SECTION_FREQUENT, FREQUENT_TITLE, FREQUENT_ICON, FREQUENT_GLYPH);
        for (int i = 0; i < GROUP_TITLES.length; i++) {
            add_category (i, GROUP_TITLES[i], GROUP_ICONS[i], GROUP_GLYPHS[i]);
        }
    }

    private void add_category (int id, string title, string icon, string glyph) {
        var button = new Gtk.Button ();
        button.relief = Gtk.ReliefStyle.NONE;
        button.can_focus = false;
        button.tooltip_text = title;
        button.get_style_context ().add_class ("emozi-category");

        if (Gtk.IconTheme.get_default ().has_icon (icon)) {
            button.image = new Gtk.Image.from_icon_name (icon, Gtk.IconSize.BUTTON);
        } else {
            button.label = glyph;
        }

        var a11y = button.get_accessible ();
        if (a11y != null) {
            a11y.set_name (title);
        }

        button.clicked.connect (() => category_selected (id));
        pack_start (button, true, true, 0);
        buttons += button;
        ids += id;
    }

    public void set_active (int section_id) {
        for (int i = 0; i < buttons.length; i++) {
            var ctx = buttons[i].get_style_context ();
            if (ids[i] == section_id) {
                ctx.add_class ("active-category");
            } else {
                ctx.remove_class ("active-category");
            }
        }
    }
}
