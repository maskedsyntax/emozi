namespace Emozi.Search {
    private class Hit {
        public unowned Emoji emoji;
        public int score;
        public double usage;

        public Hit (Emoji emoji, int score, double usage) {
            this.emoji = emoji;
            this.score = score;
            this.usage = usage;
        }
    }

    /* Score one query term against an emoji; 0 means no match. */
    private int score_term (Emoji e, string term) {
        int best = 0;

        /* whole word ("japan" → "flag: Japan") beats prefix ("Japanese …") */
        foreach (unowned string w in e.norm_name_words) {
            if (w == term) {
                best = 320;
                break;
            }
        }
        if (best == 0 && e.norm_name.has_prefix (term)) {
            best = 300;
        }
        if (best == 0) {
            foreach (unowned string w in e.norm_name_words) {
                if (w.has_prefix (term)) {
                    best = 200;
                    break;
                }
            }
        }

        if (best < 150) {
            foreach (unowned string k in e.norm_keywords) {
                if (k == term) {
                    best = 150;
                    break;
                }
                if (best < 100 && k.has_prefix (term)) {
                    best = 100;
                }
            }
        }

        if (best == 0 && term.length >= 2 && e.norm_name.contains (term)) {
            best = 50;
        }
        if (best == 0 && term.length >= 3) {
            foreach (unowned string k in e.norm_keywords) {
                if (k.contains (term)) {
                    best = 20;
                    break;
                }
            }
        }
        return best;
    }

    /* Returns emojis matching every term of `query`, best first.
     * `usage_score` (optional) breaks ties in favour of frequently used ones. */
    public GenericArray<Emoji> run (EmojiStore store, string query,
                                    UsageStore? usage = null,
                                    bool only_renderable = true) {
        var results = new GenericArray<Emoji> ();
        string q = TextUtil.normalize (query);
        if (q.length == 0) {
            return results;
        }

        /* Pasting an emoji finds it. */
        Emoji? exact = store.lookup (query.strip ());
        if (exact != null) {
            results.add (exact);
            return results;
        }

        string[] terms = q.split (" ");
        var hits = new GenericArray<Hit> ();

        store.emojis.foreach ((e) => {
            if (only_renderable && !e.renderable) {
                return;
            }
            int total = 0;
            foreach (unowned string t in terms) {
                if (t.length == 0) {
                    continue;
                }
                int s = score_term (e, t);
                if (s == 0) {
                    return;
                }
                total += s;
            }
            if (e.norm_name == q) {
                total += 1000;
            }
            /* among equal matches, shorter (more specific) names win:
             * "flag: Japan" before "map of Japan" */
            total += int.max (0, 8 - e.norm_name_words.length);
            hits.add (new Hit (e, total, usage != null ? usage.score (e) : 0.0));
        });

        hits.sort ((a, b) => {
            if (a.score != b.score) {
                return b.score - a.score;
            }
            if (a.usage != b.usage) {
                return a.usage < b.usage ? 1 : -1;
            }
            return a.emoji.index - b.emoji.index;
        });

        hits.foreach ((h) => results.add (h.emoji));
        return results;
    }
}
