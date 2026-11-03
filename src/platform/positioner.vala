/* Picks where the picker opens: under the text caret if we can find it
 * inside the active window, otherwise at the mouse pointer. The window is
 * kept fully inside the monitor's work area. Coordinates are logical
 * (GDK) pixels; AT-SPI/X11 device pixels are divided by the scale factor. */
namespace Emozi.Positioner {
    private const int GAP = 6;

    public void compute (CaretTracker? caret, bool use_caret, ulong active_window,
                         int win_w, int win_h, out int x, out int y) {
        var display = Gdk.Display.get_default ();
        Gdk.Rectangle anchor = Gdk.Rectangle ();
        bool found = false;

        if (use_caret && caret != null && active_window != 0) {
            Gdk.Rectangle r = Gdk.Rectangle ();
            Gdk.Rectangle frame = Gdk.Rectangle ();
            bool have_caret = caret.get_caret_rect (out r);
            bool have_frame = have_caret && X11.get_window_rect (active_window, out frame);
            if (have_caret && have_frame) {
                int cx = r.x, cy = r.y + r.height / 2;
                bool inside = cx >= frame.x && cx <= frame.x + frame.width &&
                              cy >= frame.y && cy <= frame.y + frame.height;
                if (inside) {
                    var mon = display.get_monitor (0);
                    int scale = mon != null ? mon.scale_factor : 1;
                    anchor.x = r.x / scale;
                    anchor.y = r.y / scale;
                    anchor.width = int.max (1, r.width / scale);
                    anchor.height = int.max (1, r.height / scale);
                    found = true;
                }
            }
        }

        if (!found) {
            int px = 0, py = 0;
            var seat = display.get_default_seat ();
            if (seat != null && seat.get_pointer () != null) {
                seat.get_pointer ().get_position (null, out px, out py);
            }
            anchor.x = px;
            anchor.y = py;
            anchor.width = 1;
            anchor.height = 1;
        }

        var monitor = display.get_monitor_at_point (anchor.x, anchor.y);
        Gdk.Rectangle work = monitor.get_workarea ();

        /* Horizontally: start a little left of the anchor; vertically: below
         * it, or above when there's no room below. */
        x = anchor.x - 24;
        y = anchor.y + anchor.height + GAP;
        if (y + win_h > work.y + work.height) {
            int above = anchor.y - win_h - GAP;
            y = above >= work.y ? above : work.y + work.height - win_h;
        }
        x = x.clamp (work.x, int.max (work.x, work.x + work.width - win_w));
        y = y.clamp (work.y, int.max (work.y, work.y + work.height - win_h));
    }
}
