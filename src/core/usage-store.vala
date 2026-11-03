/* Remembers which emojis were used (frecency) and which skin-tone variant was
 * picked for each base emoji. Persisted as a GKeyFile; keys are codepoint
 * strings because emojis like "#️⃣" would otherwise be read as comments. */
public class Emozi.UsageStore : Object {
    private const string USAGE = "usage";
    private const string TONES = "tones";
    private const double HALF_LIFE_SECONDS = 14.0 * 24 * 3600;

    /* Shown until the user has picked enough emojis of their own. */
    private const string[] DEFAULTS = {
        "😂", "❤️", "👍", "😭", "🙏", "😘", "🥰", "😍", "😊",
        "🎉", "🔥", "😁", "✨", "💯", "😅", "🤔", "👏", "😎"
    };

    private string? path;
    private KeyFile kf = new KeyFile ();

    /* `path` null → in-memory only (tests). */
    public UsageStore (string? path) {
        this.path = path;
        if (path == null) {
            return;
        }
        try {
            kf.load_from_file (path, KeyFileFlags.NONE);
        } catch (FileError.NOENT e) {
            /* first run */
        } catch (Error e) {
            warning ("Ignoring unreadable usage file %s: %s", path, e.message);
            kf = new KeyFile ();
        }
    }

    private static double decay (double score, int64 last, int64 now) {
        double age = (double) (now - last);
        if (age <= 0) {
            return score;
        }
        return score * Math.pow (0.5, age / HALF_LIFE_SECONDS);
    }

    private bool read_entry (string key, out double score, out int64 last) {
        score = 0;
        last = 0;
        try {
            string v = kf.get_string (USAGE, key);
            string[] parts = v.split (";");
            if (parts.length != 2) {
                return false;
            }
            score = double.parse (parts[0]);
            last = int64.parse (parts[1]);
            return true;
        } catch (Error e) {
            return false;
        }
    }

    public double score (Emoji e, int64 now = -1) {
        if (now < 0) {
            now = get_real_time () / 1000000;
        }
        double s;
        int64 last;
        if (!read_entry (TextUtil.to_key (e.text), out s, out last)) {
            return 0;
        }
        return decay (s, last, now);
    }

    /* Record that `chosen` (base or variant of `e`) was inserted. */
    public void record (Emoji e, string chosen, int64 now = -1) {
        if (now < 0) {
            now = get_real_time () / 1000000;
        }
        string key = TextUtil.to_key (e.text);
        double s;
        int64 last;
        read_entry (key, out s, out last);
        double updated = decay (s, last, now) + 1.0;
        kf.set_string (USAGE, key, "%.4f;%lld".printf (updated, now));

        if (e.variants.length > 0) {
            kf.set_string (TONES, key, TextUtil.to_key (chosen));
        }
        save ();
    }

    /* The variant last picked for `e`, or null if none was. */
    public string? preferred_variant (Emoji e) {
        if (e.variants.length == 0) {
            return null;
        }
        try {
            string want = kf.get_string (TONES, TextUtil.to_key (e.text));
            if (want == TextUtil.to_key (e.text)) {
                return e.text;
            }
            foreach (unowned string v in e.variants) {
                if (TextUtil.to_key (v) == want) {
                    return v;
                }
            }
        } catch (Error err) {
        }
        return null;
    }

    /* Most-used emojis first, padded with popular defaults. */
    public GenericArray<Emoji> frequent (EmojiStore store, int limit, int64 now = -1) {
        if (now < 0) {
            now = get_real_time () / 1000000;
        }
        var result = new GenericArray<Emoji> ();
        var seen = new GenericSet<Emoji> (direct_hash, direct_equal);

        string[] keys = {};
        try {
            if (kf.has_group (USAGE)) {
                keys = kf.get_keys (USAGE);
            }
        } catch (Error e) {
        }

        var scored = new GenericArray<Emoji> ();
        var scores = new HashTable<Emoji, double?> (direct_hash, direct_equal);
        foreach (unowned string key in keys) {
            var sb = new StringBuilder ();
            foreach (unowned string hex in key.split ("-")) {
                sb.append_unichar ((unichar) ulong.parse (hex, 16));
            }
            Emoji? e = store.lookup (sb.str);
            if (e == null || !e.renderable || scores.contains (e)) {
                continue;
            }
            scores.insert (e, score (e, now));
            scored.add (e);
        }
        scored.sort_with_data ((a, b) => {
            double sa = scores.lookup (a), sb2 = scores.lookup (b);
            if (sa != sb2) {
                return sa < sb2 ? 1 : -1;
            }
            return a.index - b.index;
        });

        for (uint i = 0; i < scored.length && result.length < limit; i++) {
            result.add (scored[i]);
            seen.add (scored[i]);
        }
        foreach (unowned string d in DEFAULTS) {
            if (result.length >= limit) {
                break;
            }
            Emoji? e = store.lookup (d);
            if (e != null && e.renderable && !seen.contains (e)) {
                result.add (e);
                seen.add (e);
            }
        }
        return result;
    }

    private void save () {
        if (path == null) {
            return;
        }
        try {
            DirUtils.create_with_parents (Path.get_dirname (path), 0700);
            kf.save_to_file (path);
        } catch (Error e) {
            warning ("Could not save usage to %s: %s", path, e.message);
        }
    }
}
