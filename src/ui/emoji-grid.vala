namespace Emozi {
    public class GridItem {
        public unowned Emoji emoji;
        public string text; /* what is drawn and inserted (may be a variant) */

        public GridItem (Emoji emoji, string text) {
            this.emoji = emoji;
            this.text = text;
        }
    }

    public class GridSection {
        public int id;
        public string title;
        public GenericArray<GridItem> items = new GenericArray<GridItem> ();
        internal int y;          /* top of header (or first row) */
        internal int first_item; /* global index */

        public GridSection (int id, string title) {
            this.id = id;
            this.title = title;
        }
    }

    public enum Move { LEFT, RIGHT, UP, DOWN, PAGE_UP, PAGE_DOWN, HOME, END }

    /* A virtualized emoji grid: only visible rows are drawn, so thousands of
     * emojis cost nothing. Implements GtkScrollable so it goes straight into
     * a GtkScrolledWindow without a viewport, and draws sticky headers. */
    public class EmojiGrid : Gtk.DrawingArea, Gtk.Scrollable {
        private const int CELL = 40;
        private const int EMOJI_PX = 26;
        private const int HEADER_H = 28;
        private const int PAD = 6;
        private const int SECTION_GAP = 4;

        public signal void item_activated (GridItem item);
        public signal void item_context (GridItem item, Gdk.Rectangle rect);
        public signal void selection_changed (GridItem? item);
        public signal void top_section_changed (int section_id);

        public bool show_headers { get; set; default = true; }
        public string empty_text { get; set; default = "No Emoji Found"; }

        /* GtkScrollable */
        private Gtk.Adjustment? _hadj;
        private Gtk.Adjustment? _vadj;
        public Gtk.Adjustment hadjustment {
            get { return _hadj; }
            set construct { _hadj = value; }
        }
        public Gtk.Adjustment vadjustment {
            get { return _vadj; }
            set construct {
                if (_vadj != null) {
                    _vadj.value_changed.disconnect (on_scrolled);
                }
                _vadj = value;
                if (_vadj != null) {
                    _vadj.value_changed.connect (on_scrolled);
                    configure_adjustment ();
                }
            }
        }
        public Gtk.ScrollablePolicy hscroll_policy { get; set; }
        public Gtk.ScrollablePolicy vscroll_policy { get; set; }

        public bool get_border (out Gtk.Border border) {
            border = Gtk.Border ();
            return false;
        }

        private GridSection[] sections = {};
        private GridItem[] items = {};
        private int[] item_row = {};
        private int[] item_col = {};
        private int[] row_y = {};
        private int[] row_first = {};
        private int[] row_len = {};
        private int cols = 1;
        private double cell_w = CELL;
        private int content_height = 0;
        private int layout_width = -1;

        private int selected = -1;
        private int top_section_id = int.MIN;

        private HashTable<string, Pango.Layout> layout_cache =
            new HashTable<string, Pango.Layout> (str_hash, str_equal);
        private Pango.FontDescription emoji_font;
        private Pango.FontDescription header_font;

        private Gtk.GestureLongPress long_press;
        private bool long_pressed = false;
        private int press_index = -1;
        private double last_motion_x = double.NAN;
        private double last_motion_y = double.NAN;

        construct {
            can_focus = false;
            add_events (Gdk.EventMask.POINTER_MOTION_MASK |
                        Gdk.EventMask.BUTTON_PRESS_MASK |
                        Gdk.EventMask.BUTTON_RELEASE_MASK |
                        Gdk.EventMask.LEAVE_NOTIFY_MASK);
            update_fonts ();

            long_press = new Gtk.GestureLongPress (this);
            long_press.touch_only = false;
            long_press.set_propagation_phase (Gtk.PropagationPhase.CAPTURE);
            long_press.pressed.connect ((x, y) => {
                int i = hit_test (x, y);
                if (i >= 0) {
                    long_pressed = true;
                    select (i, false);
                    item_context (items[i], item_rect (i));
                }
            });
        }

        /* ---------- model ---------- */

        public void set_sections (GridSection[] new_sections) {
            sections = new_sections;
            int n = 0;
            foreach (var s in sections) {
                n += (int) s.items.length;
            }
            items = new GridItem[n];
            int k = 0;
            foreach (var s in sections) {
                s.first_item = k;
                for (uint i = 0; i < s.items.length; i++) {
                    items[k++] = s.items[i];
                }
            }
            layout_width = -1;
            relayout ();
            selected = -1;
            if (items.length > 0) {
                select (0, false);
            } else {
                selection_changed (null); /* clear the status line */
            }
            if (_vadj != null) {
                _vadj.value = 0;
            }
            top_section_id = int.MIN;
            update_top_section ();
            queue_draw ();
        }

        public GridItem? selected_item {
            get { return selected >= 0 && selected < items.length ? items[selected] : null; }
        }

        public int selected_index {
            get { return selected; }
        }

        public int item_count {
            get { return items.length; }
        }

        /* Replace the item at the current selection (e.g. after picking a tone). */
        public void update_text (Emoji emoji, string text) {
            foreach (var it in items) {
                if (it.emoji == emoji) {
                    it.text = text;
                }
            }
            queue_draw ();
        }

        /* ---------- layout ---------- */

        private void update_fonts () {
            var base_font = get_style_context ().get_font (Gtk.StateFlags.NORMAL);
            emoji_font = base_font.copy ();
            emoji_font.set_absolute_size (EMOJI_PX * Pango.SCALE);
            header_font = base_font.copy ();
            header_font.set_weight (Pango.Weight.BOLD);
            header_font.set_size ((int) (base_font.get_size () * 0.85));
            layout_cache.remove_all ();
        }

        public Pango.FontDescription get_emoji_font () {
            return emoji_font.copy ();
        }

        public override void style_updated () {
            base.style_updated ();
            update_fonts ();
            queue_draw ();
        }

        public override void screen_changed (Gdk.Screen? previous) {
            /* no chain-up: GtkWidget has no default handler (NULL vfunc) */
            layout_cache.remove_all ();
        }

        private void relayout () {
            int width = get_allocated_width ();
            if (width <= 1) {
                width = 360;
            }
            if (width == layout_width) {
                return;
            }
            layout_width = width;
            cols = int.max (1, (width - 2 * PAD) / CELL);
            cell_w = (double) (width - 2 * PAD) / cols;

            int[] ir = new int[items.length];
            int[] ic = new int[items.length];
            int[] ry = {};
            int[] rf = {};
            int[] rl = {};
            int y = 0;
            foreach (var s in sections) {
                s.y = y;
                if (s.items.length == 0) {
                    continue;
                }
                if (show_headers) {
                    y += HEADER_H;
                }
                for (int i = 0; i < s.items.length; i++) {
                    int g = s.first_item + i;
                    if (i % cols == 0) {
                        ry += y;
                        rf += g;
                        rl += int.min (cols, (int) s.items.length - i);
                        y += CELL;
                    }
                    ir[g] = ry.length - 1;
                    ic[g] = i % cols;
                }
                y += SECTION_GAP;
            }
            item_row = ir;
            item_col = ic;
            row_y = ry;
            row_first = rf;
            row_len = rl;
            content_height = y + PAD;
            configure_adjustment ();
        }

        private void configure_adjustment () {
            if (_vadj == null) {
                return;
            }
            int h = int.max (1, get_allocated_height ());
            double upper = double.max (content_height, h);
            double value = _vadj.value.clamp (0, upper - h);
            _vadj.configure (value, 0, upper, CELL * 0.5, h * 0.9, h);
        }

        public override void size_allocate (Gtk.Allocation alloc) {
            base.size_allocate (alloc);
            relayout ();
            configure_adjustment ();
        }

        public override void get_preferred_width (out int min, out int nat) {
            min = CELL * 4 + 2 * PAD;
            nat = CELL * 9 + 2 * PAD;
        }

        public override void get_preferred_height (out int min, out int nat) {
            min = CELL * 3;
            nat = CELL * 8;
        }

        private double offset {
            get { return _vadj != null ? _vadj.value : 0; }
        }

        public Gdk.Rectangle item_rect (int i) {
            Gdk.Rectangle r = Gdk.Rectangle ();
            r.x = (int) (PAD + item_col[i] * cell_w);
            r.y = (int) (row_y[item_row[i]] - offset);
            r.width = (int) cell_w;
            r.height = CELL;
            return r;
        }

        private int hit_test (double x, double y) {
            double cy = y + offset;
            int lo = 0, hi = row_y.length - 1, row = -1;
            while (lo <= hi) {
                int mid = (lo + hi) / 2;
                if (row_y[mid] <= cy) {
                    row = mid;
                    lo = mid + 1;
                } else {
                    hi = mid - 1;
                }
            }
            if (row < 0 || cy >= row_y[row] + CELL) {
                return -1;
            }
            if (show_headers && y < HEADER_H && current_section_index () >= 0) {
                return -1; /* under the sticky header */
            }
            int col = (int) Math.floor ((x - PAD) / cell_w);
            if (col < 0 || col >= row_len[row]) {
                return -1;
            }
            return row_first[row] + col;
        }

        /* ---------- drawing ---------- */

        private Pango.Layout get_layout (string text) {
            Pango.Layout? l = layout_cache.lookup (text);
            if (l == null) {
                l = create_pango_layout (text);
                l.set_font_description (emoji_font);
                layout_cache.insert (text, l);
            }
            return l;
        }

        private Gdk.RGBA lookup (string name, string fallback) {
            Gdk.RGBA c;
            if (!get_style_context ().lookup_color (name, out c)) {
                c = Gdk.RGBA ();
                c.parse (fallback);
            }
            return c;
        }

        private static void rounded_rect (Cairo.Context cr, double x, double y,
                                          double w, double h, double r) {
            cr.new_sub_path ();
            cr.arc (x + w - r, y + r, r, -Math.PI / 2, 0);
            cr.arc (x + w - r, y + h - r, r, 0, Math.PI / 2);
            cr.arc (x + r, y + h - r, r, Math.PI / 2, Math.PI);
            cr.arc (x + r, y + r, r, Math.PI, 3 * Math.PI / 2);
            cr.close_path ();
        }

        private int current_section_index () {
            int idx = -1;
            double top = offset;
            for (int i = 0; i < sections.length; i++) {
                if (sections[i].items.length == 0) {
                    continue;
                }
                if (sections[i].y <= top) {
                    idx = i;
                } else {
                    break;
                }
            }
            return idx;
        }

        public override bool draw (Cairo.Context cr) {
            int width = get_allocated_width ();
            int height = get_allocated_height ();
            var ctx = get_style_context ();
            Gdk.RGBA fg = ctx.get_color (ctx.get_state ());
            Gdk.RGBA sel = lookup ("theme_selected_bg_color", "#3584e4");
            Gdk.RGBA bg = lookup ("theme_bg_color", "#ffffff");
            double off = offset;

            if (items.length == 0) {
                var l = create_pango_layout (empty_text);
                int lw, lh;
                l.get_pixel_size (out lw, out lh);
                cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.55);
                cr.move_to ((width - lw) / 2.0, (height - lh) / 2.0);
                Pango.cairo_show_layout (cr, l);
                return false;
            }

            /* rows */
            for (int r = 0; r < row_y.length; r++) {
                double y = row_y[r] - off;
                if (y + CELL < 0) {
                    continue;
                }
                if (y > height) {
                    break;
                }
                for (int c = 0; c < row_len[r]; c++) {
                    int i = row_first[r] + c;
                    double x = PAD + c * cell_w;
                    if (i == selected) {
                        cr.set_source_rgba (sel.red, sel.green, sel.blue, 0.35);
                        rounded_rect (cr, x + 1, y + 1, cell_w - 2, CELL - 2, 6);
                        cr.fill ();
                    }
                    var l = get_layout (items[i].text);
                    int lw, lh;
                    l.get_pixel_size (out lw, out lh);
                    cr.set_source_rgba (fg.red, fg.green, fg.blue, fg.alpha);
                    cr.move_to (x + (cell_w - lw) / 2.0, y + (CELL - lh) / 2.0);
                    Pango.cairo_show_layout (cr, l);
                }
            }

            if (!show_headers) {
                return false;
            }

            /* inline headers */
            foreach (var s in sections) {
                if (s.items.length == 0) {
                    continue;
                }
                double y = s.y - off;
                if (y + HEADER_H < 0 || y > height) {
                    continue;
                }
                draw_header (cr, s.title, y, width, fg, bg);
            }

            /* sticky header, pushed up by the next one */
            int cur = current_section_index ();
            if (cur >= 0 && sections[cur].y < off) {
                double y = 0;
                for (int j = cur + 1; j < sections.length; j++) {
                    if (sections[j].items.length > 0) {
                        y = double.min (0, sections[j].y - off - HEADER_H);
                        break;
                    }
                }
                draw_header (cr, sections[cur].title, y, width, fg, bg);
            }
            return false;
        }

        private void draw_header (Cairo.Context cr, string title, double y, int width,
                                  Gdk.RGBA fg, Gdk.RGBA bg) {
            cr.set_source_rgba (bg.red, bg.green, bg.blue, 1.0);
            cr.rectangle (0, y, width, HEADER_H);
            cr.fill ();
            var l = create_pango_layout (title);
            l.set_font_description (header_font);
            int lw, lh;
            l.get_pixel_size (out lw, out lh);
            cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.6);
            cr.move_to (PAD + 4, y + (HEADER_H - lh) / 2.0);
            Pango.cairo_show_layout (cr, l);
        }

        /* ---------- scrolling ---------- */

        private void on_scrolled () {
            update_top_section ();
            queue_draw ();
        }

        private void update_top_section () {
            int idx = current_section_index ();
            /* at the very bottom, the last section is "current" even if its
             * header never reaches the top */
            if (_vadj != null && sections.length > 0 &&
                _vadj.value >= _vadj.upper - _vadj.page_size - 1) {
                for (int j = sections.length - 1; j >= 0; j--) {
                    if (sections[j].items.length > 0) {
                        idx = j;
                        break;
                    }
                }
            }
            int id = idx >= 0 ? sections[idx].id : (sections.length > 0 ? sections[0].id : int.MIN);
            if (id != top_section_id) {
                top_section_id = id;
                top_section_changed (id);
            }
        }

        public void scroll_to_section (int id) {
            foreach (var s in sections) {
                if (s.id == id && s.items.length > 0) {
                    if (_vadj != null) {
                        _vadj.value = s.y;
                    }
                    select (s.first_item, false);
                    return;
                }
            }
        }

        private void ensure_visible (int i) {
            if (_vadj == null || i < 0) {
                return;
            }
            double y = row_y[item_row[i]];
            double h = get_allocated_height ();
            double top_margin = show_headers ? HEADER_H : 0;
            if (y - top_margin < _vadj.value) {
                /* show the section header if this is its first row */
                double target = y - top_margin;
                foreach (var s in sections) {
                    if (s.first_item == row_first[item_row[i]]) {
                        target = s.y;
                    }
                }
                _vadj.value = double.max (0, target);
            } else if (y + CELL > _vadj.value + h) {
                _vadj.value = y + CELL - h + PAD;
            }
        }

        /* ---------- selection & keyboard ---------- */

        public void select (int i, bool scroll = true) {
            if (i >= items.length) {
                i = items.length - 1;
            }
            if (i == selected) {
                return;
            }
            selected = i;
            if (scroll) {
                ensure_visible (i);
            }
            queue_draw ();
            selection_changed (selected_item);
        }

        public void move (Move m) {
            if (items.length == 0) {
                return;
            }
            if (selected < 0) {
                select (0);
                return;
            }
            int row = item_row[selected];
            int col = item_col[selected];
            int page_rows = int.max (1, get_allocated_height () / CELL - 1);
            int target = selected;

            switch (m) {
            case Move.LEFT:
                target = int.max (0, selected - 1);
                break;
            case Move.RIGHT:
                target = int.min (items.length - 1, selected + 1);
                break;
            case Move.UP:
                target = row > 0 ? row_first[row - 1] + int.min (col, row_len[row - 1] - 1) : selected;
                break;
            case Move.DOWN:
                target = row < row_y.length - 1
                    ? row_first[row + 1] + int.min (col, row_len[row + 1] - 1) : selected;
                break;
            case Move.PAGE_UP:
                int r = int.max (0, row - page_rows);
                target = row_first[r] + int.min (col, row_len[r] - 1);
                break;
            case Move.PAGE_DOWN:
                int r = int.min (row_y.length - 1, row + page_rows);
                target = row_first[r] + int.min (col, row_len[r] - 1);
                break;
            case Move.HOME:
                target = 0;
                break;
            case Move.END:
                target = items.length - 1;
                break;
            }
            select (target);
        }

        /* Call before showing: the first motion event after mapping (which
         * happens when the window pops up under the pointer) must not steal
         * the selection from the first item. */
        public void reset_pointer_tracking () {
            last_motion_x = double.NAN;
            last_motion_y = double.NAN;
        }

        /* ---------- mouse ---------- */

        public override bool motion_notify_event (Gdk.EventMotion ev) {
            if (last_motion_x.is_nan ()) {
                last_motion_x = ev.x_root;
                last_motion_y = ev.y_root;
                return false;
            }
            if (ev.x_root == last_motion_x && ev.y_root == last_motion_y) {
                return false;
            }
            last_motion_x = ev.x_root;
            last_motion_y = ev.y_root;
            int i = hit_test (ev.x, ev.y);
            if (i >= 0) {
                select (i, false);
            }
            return false;
        }

        public override bool button_press_event (Gdk.EventButton ev) {
            int i = hit_test (ev.x, ev.y);
            if (ev.type != Gdk.EventType.BUTTON_PRESS || i < 0) {
                press_index = -1;
                return false;
            }
            if (ev.button == Gdk.BUTTON_SECONDARY) {
                select (i, false);
                item_context (items[i], item_rect (i));
                press_index = -1;
                return true;
            }
            if (ev.button == Gdk.BUTTON_PRIMARY) {
                long_pressed = false;
                press_index = i;
                select (i, false);
            }
            return false;
        }

        public override bool button_release_event (Gdk.EventButton ev) {
            if (ev.button != Gdk.BUTTON_PRIMARY) {
                return false;
            }
            int i = hit_test (ev.x, ev.y);
            bool activate = !long_pressed && i >= 0 && i == press_index;
            press_index = -1;
            long_pressed = false;
            if (activate) {
                item_activated (items[i]);
            }
            return activate;
        }
    }
}
