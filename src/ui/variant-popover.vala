/* Skin-tone chooser: the base emoji, then its variants (one row of 5, or a
 * 5×5 grid for two-person emojis where rows = first person's tone). */
public class Emozi.VariantPopover : Gtk.Popover {
    public signal void chosen (string text);

    public VariantPopover (Gtk.Widget relative_to, Gdk.Rectangle rect, Emoji emoji, string current) {
        Object (relative_to: relative_to, position: Gtk.PositionType.BOTTOM);
        pointing_to = rect;
        get_style_context ().add_class ("emozi-variants");

        var grid = new Gtk.Grid ();
        grid.row_spacing = 2;
        grid.column_spacing = 2;
        grid.margin = 6;

        Gtk.Button? focus = null;
        var base_button = make_button (emoji.text, emoji.display_name);
        grid.attach (base_button, 0, 0, 1, 1);
        if (current == emoji.text) {
            focus = base_button;
        }

        string[] vs = emoji.renderable_variants;
        bool two_person = emoji.variants.length == 25 && vs.length == 25;
        for (int i = 0; i < vs.length; i++) {
            var b = make_button (vs[i], emoji.display_name);
            if (two_person) {
                grid.attach (b, i % 5, 1 + i / 5, 1, 1);
            } else {
                grid.attach (b, 1 + i, 0, 1, 1);
            }
            if (vs[i] == current) {
                focus = b;
            }
        }

        grid.show_all ();
        add (grid);
        if (focus != null) {
            focus.grab_focus ();
        }
    }

    private Gtk.Button make_button (string text, string name) {
        var b = new Gtk.Button.with_label (text);
        b.relief = Gtk.ReliefStyle.NONE;
        b.get_style_context ().add_class ("emozi-variant");
        b.tooltip_text = name;
        b.clicked.connect (() => {
            chosen (text);
            popdown ();
        });
        return b;
    }
}
