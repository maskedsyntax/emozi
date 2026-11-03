/* Finds the text caret of the focused widget in other apps via AT-SPI, so
 * the picker can open right under it (like macOS). We only listen for focus
 * changes (cheap) and query the caret on demand. Anything that fails or
 * looks stale returns false, and the caller falls back to the pointer. */
public class Emozi.CaretTracker : Object {
    private Atspi.EventListener? listener = null;
    private Atspi.Accessible? focused = null;
    public bool paused { get; set; default = false; }

    public CaretTracker () {
        if (Atspi.init () > 1) {
            debug ("AT-SPI unavailable; caret positioning disabled");
            return;
        }
        /* Never block the UI on a hung application. */
        Atspi.set_timeout (150, 1000);
        listener = new Atspi.EventListener (on_event);
        try {
            listener.register ("object:state-changed:focused");
        } catch (Error e) {
            debug ("AT-SPI listener failed: %s", e.message);
            listener = null;
        }
    }

    private void on_event (owned Atspi.Event ev) {
        if (paused || ev.detail1 != 1 || ev.source == null) {
            return;
        }
        focused = ev.source;
    }

    /* Caret rectangle in X11 root (device pixel) coordinates. */
    public bool get_caret_rect (out Gdk.Rectangle rect) {
        rect = Gdk.Rectangle ();
        if (listener == null || focused == null) {
            return false;
        }
        try {
            Atspi.Text? text = focused.get_text_iface ();
            if (text == null) {
                return false;
            }
            int offset = text.get_caret_offset ();
            if (offset < 0) {
                return false;
            }
            Atspi.Rect r = text.get_character_extents (offset, Atspi.CoordType.SCREEN);
            if (r.width <= 0 && r.height <= 0 && offset > 0) {
                /* caret at end of text: use the previous character's right edge */
                Atspi.Rect p = text.get_character_extents (offset - 1, Atspi.CoordType.SCREEN);
                r.x = p.x + p.width;
                r.y = p.y;
                r.width = 1;
                r.height = p.height;
            }
            if (r.height <= 0 || (r.x <= 0 && r.y <= 0)) {
                return false;
            }
            rect.x = r.x;
            rect.y = r.y;
            rect.width = int.max (1, r.width);
            rect.height = r.height;
            return true;
        } catch (Error e) {
            debug ("caret query failed: %s", e.message);
            return false;
        }
    }
}
