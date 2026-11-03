/* Decides which emojis the installed fonts can actually draw.
 *
 * An emoji counts as renderable when Pango shapes it with no unknown glyphs,
 * into exactly one visible glyph, using the same font as a known-good
 * reference emoji. Unsupported ZWJ sequences fall apart into several glyphs
 * and unsupported flags into two letters, so both are caught. */
namespace Emozi.Coverage {
    private bool check (Pango.Layout layout, string text, string ref_family) {
        layout.set_text (text, -1);
        if (layout.get_unknown_glyphs_count () > 0) {
            return false;
        }
        int visible = 0;
        Pango.LayoutIter iter = layout.get_iter ();
        do {
            unowned Pango.LayoutRun? run = iter.get_run_readonly ();
            if (run == null) {
                continue;
            }
            unowned Pango.GlyphString gs = run.glyphs;
            for (int i = 0; i < gs.num_glyphs; i++) {
                if (gs.glyphs[i].geometry.width > 0) {
                    visible++;
                }
            }
            /* keep the description alive while reading its family string */
            Pango.FontDescription desc = run.item.analysis.font.describe ();
            if (desc.get_family () != ref_family) {
                return false;
            }
        } while (iter.next_run ());
        return visible == 1;
    }

    private string? family_of (Pango.Layout layout, string text) {
        layout.set_text (text, -1);
        unowned Pango.LayoutRun? run = layout.get_iter ().get_run_readonly ();
        if (run == null) {
            return null;
        }
        Pango.FontDescription desc = run.item.analysis.font.describe ();
        return desc.get_family ();
    }

    /* Returns the number of hidden emojis (base + variants). */
    public int compute (EmojiStore store, Pango.Context context, Pango.FontDescription font) {
        var layout = new Pango.Layout (context);
        layout.set_font_description (font);

        string? ref_family = family_of (layout, "😀");
        if (ref_family == null) {
            warning ("No font can render emoji; showing everything");
            return 0;
        }
        debug ("Emoji font: %s", ref_family);

        int hidden = 0;
        store.emojis.foreach ((e) => {
            e.renderable = check (layout, e.text, ref_family);
            if (!e.renderable) {
                hidden++;
                debug ("Hidden (no font support): %s %s E%s", e.text, e.name, e.version);
            }
            string[] ok = {};
            foreach (unowned string v in e.variants) {
                if (e.renderable && check (layout, v, ref_family)) {
                    ok += v;
                } else {
                    hidden++;
                }
            }
            e.renderable_variants = ok;
        });
        return hidden;
    }
}
