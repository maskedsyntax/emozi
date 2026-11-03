/* The picker popup: search entry, emoji grid, status line and category bar.
 * Keyboard focus always stays in the search entry (like macOS); navigation
 * keys are routed to the grid by key_press_event. */
public class Emozi.PickerWindow : Gtk.Window {
    public const int WIDTH = 372;
    public const int HEIGHT = 440;
    private const int FREQUENT_COLUMNS = 9;

    /* `text` is what to insert: the base emoji or one of its variants. */
    public signal void emoji_chosen (Emoji emoji, string text);
    public signal void dismissed ();

    private EmojiStore store;
    private UsageStore usage;
    private Config config;

    private Gtk.SearchEntry entry;
    private EmojiGrid grid;
    private CategoryBar bar;
    private Gtk.Label status;
    private VariantPopover? popover = null;

    public PickerWindow (Gtk.Application app, EmojiStore store, UsageStore usage, Config config) {
        Object (application: app, type: Gtk.WindowType.TOPLEVEL);
        this.store = store;
        this.usage = usage;
        this.config = config;

        title = "Emoji";
        icon_name = BuildConfig.APP_ID;
        decorated = false;
        resizable = false;
        skip_taskbar_hint = true;
        skip_pager_hint = true;
        set_keep_above (true);
        set_size_request (WIDTH, HEIGHT);
        get_style_context ().add_class ("emozi-window");

        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);

        entry = new Gtk.SearchEntry ();
        entry.placeholder_text = "Search";
        entry.margin = 8;
        entry.margin_bottom = 4;
        entry.changed.connect (on_search_changed);
        box.pack_start (entry, false, false, 0);

        grid = new EmojiGrid ();
        grid.item_activated.connect ((item) => emoji_chosen (item.emoji, item.text));
        grid.item_context.connect (open_variants);
        grid.selection_changed.connect (update_status);
        grid.top_section_changed.connect ((id) => bar.set_active (id));

        var scroller = new Gtk.ScrolledWindow (null, null);
        scroller.hscrollbar_policy = Gtk.PolicyType.NEVER;
        scroller.vscrollbar_policy = Gtk.PolicyType.AUTOMATIC;
        scroller.add (grid);
        box.pack_start (scroller, true, true, 0);

        status = new Gtk.Label ("");
        status.halign = Gtk.Align.START;
        status.ellipsize = Pango.EllipsizeMode.END;
        status.margin_start = 12;
        status.margin_end = 12;
        status.margin_top = 2;
        status.margin_bottom = 2;
        status.get_style_context ().add_class ("emozi-status");
        box.pack_start (status, false, false, 0);

        box.pack_start (new Gtk.Separator (Gtk.Orientation.HORIZONTAL), false, false, 0);

        bar = new CategoryBar ();
        bar.margin = 4;
        bar.category_selected.connect ((id) => {
            if (entry.text != "") {
                entry.text = "";
            }
            grid.scroll_to_section (id);
        });
        box.pack_start (bar, false, false, 0);

        add (box);
        box.show_all ();

        delete_event.connect (() => {
            dismiss ();
            return true;
        });

        show_browse ();
    }

    /* ---------- content ---------- */

    private string display_text (Emoji e) {
        if (!e.has_variants) {
            return e.text;
        }
        string? pref = usage.preferred_variant (e);
        if (pref != null && (pref == e.text || pref in e.renderable_variants)) {
            return pref;
        }
        string? toned = e.variant_for_tone (config.default_skin_tone);
        if (toned != null && toned in e.renderable_variants) {
            return toned;
        }
        return e.text;
    }

    private void show_browse () {
        GridSection[] sections = {};

        if (config.frequent_rows > 0) {
            var freq = new GridSection (SECTION_FREQUENT, FREQUENT_TITLE);
            usage.frequent (store, config.frequent_rows * FREQUENT_COLUMNS).foreach ((e) => {
                freq.items.add (new GridItem (e, display_text (e)));
            });
            sections += freq;
        }

        for (int g = 0; g < GROUP_TITLES.length; g++) {
            sections += new GridSection (g, GROUP_TITLES[g]);
        }
        store.emojis.foreach ((e) => {
            if (e.renderable) {
                sections[e.group + (config.frequent_rows > 0 ? 1 : 0)].items.add (
                    new GridItem (e, display_text (e)));
            }
        });

        grid.show_headers = true;
        grid.set_sections (sections);
        bar.sensitive = true;
    }

    private void on_search_changed () {
        string q = entry.text.strip ();
        if (q.length == 0) {
            show_browse ();
            return;
        }
        var results = Search.run (store, q, usage);
        var section = new GridSection (SECTION_SEARCH, "Search Results");
        results.foreach ((e) => section.items.add (new GridItem (e, display_text (e))));
        grid.show_headers = false;
        grid.set_sections ({ section });
        bar.set_active (int.MIN);
        bar.sensitive = false;
    }

    private void update_status (GridItem? item) {
        if (item == null) {
            status.label = "";
            return;
        }
        status.label = item.emoji.display_name;
        status.tooltip_text = item.emoji.shortcode;
    }

    /* ---------- variants ---------- */

    private void open_variants (GridItem item, Gdk.Rectangle rect) {
        if (!item.emoji.has_variants) {
            return;
        }
        if (popover != null) {
            popover.destroy ();
        }
        var p = new VariantPopover (grid, rect, item.emoji, item.text);
        unowned Emoji e = item.emoji;
        p.chosen.connect ((text) => {
            grid.update_text (e, text);
            emoji_chosen (e, text);
        });
        p.closed.connect (() => {
            entry.grab_focus_without_selecting ();
            Idle.add (() => {
                if (popover == p) {
                    popover = null;
                }
                p.destroy ();
                return Source.REMOVE;
            });
        });
        popover = p;
        p.popup ();
    }

    /* ---------- show / hide ---------- */

    /* Reset to the initial state; call right before showing. */
    public void prepare () {
        if (popover != null) {
            popover.popdown ();
        }
        if (entry.text != "") {
            entry.text = ""; /* triggers show_browse */
        } else {
            show_browse ();
        }
        grid.reset_pointer_tracking ();
        entry.grab_focus ();
    }

    public void dismiss () {
        hide ();
        dismissed ();
    }

    public override bool focus_out_event (Gdk.EventFocus ev) {
        base.focus_out_event (ev);
        /* Clicking another window closes the picker, like a popover. */
        Idle.add (() => {
            if (visible && !is_active) {
                dismiss ();
            }
            return Source.REMOVE;
        });
        return false;
    }

    /* ---------- keyboard ---------- */

    public override bool key_press_event (Gdk.EventKey ev) {
        if (popover != null && popover.visible) {
            return base.key_press_event (ev);
        }
        var mods = ev.state & Gtk.accelerator_get_default_mod_mask ();
        bool shift = (mods & Gdk.ModifierType.SHIFT_MASK) != 0;
        bool ctrl = (mods & Gdk.ModifierType.CONTROL_MASK) != 0;

        switch (ev.keyval) {
        case Gdk.Key.Escape:
            if (entry.text != "") {
                entry.text = "";
            } else {
                dismiss ();
            }
            return true;
        case Gdk.Key.Up:
        case Gdk.Key.KP_Up:
            grid.move (Move.UP);
            return true;
        case Gdk.Key.Down:
        case Gdk.Key.KP_Down:
            grid.move (Move.DOWN);
            return true;
        case Gdk.Key.Left:
        case Gdk.Key.KP_Left:
            grid.move (Move.LEFT);
            return true;
        case Gdk.Key.Right:
        case Gdk.Key.KP_Right:
            grid.move (Move.RIGHT);
            return true;
        case Gdk.Key.Page_Up:
        case Gdk.Key.KP_Page_Up:
            grid.move (Move.PAGE_UP);
            return true;
        case Gdk.Key.Page_Down:
        case Gdk.Key.KP_Page_Down:
            grid.move (Move.PAGE_DOWN);
            return true;
        case Gdk.Key.Tab:
        case Gdk.Key.ISO_Left_Tab:
            grid.move (shift ? Move.LEFT : Move.RIGHT);
            return true;
        case Gdk.Key.Return:
        case Gdk.Key.KP_Enter:
        case Gdk.Key.ISO_Enter:
            var item = grid.selected_item;
            if (item != null) {
                if (shift && item.emoji.has_variants) {
                    open_variants (item, grid.item_rect (index_of_selected ()));
                } else {
                    emoji_chosen (item.emoji, item.text);
                }
            }
            return true;
        case Gdk.Key.Menu:
            var item = grid.selected_item;
            if (item != null) {
                open_variants (item, grid.item_rect (index_of_selected ()));
            }
            return true;
        }

        if (ctrl && (ev.keyval == Gdk.Key.w || ev.keyval == Gdk.Key.q)) {
            dismiss ();
            return true;
        }
        return base.key_press_event (ev);
    }

    private int index_of_selected () {
        return grid.selected_index;
    }

    public Pango.FontDescription get_emoji_font () {
        return grid.get_emoji_font ();
    }

    public Pango.Context get_grid_pango_context () {
        return grid.get_pango_context ();
    }
}
