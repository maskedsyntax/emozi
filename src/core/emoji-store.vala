public class Emozi.EmojiStore : Object {
    public const string RESOURCE_PATH = "/io/github/maskedsyntax/Emozi/emoji-data.tsv";

    public GenericArray<Emoji> emojis { get; private set; }
    private HashTable<string, Emoji> by_text;

    public EmojiStore.from_resource () throws Error {
        Bytes bytes = resources_lookup_data (RESOURCE_PATH, ResourceLookupFlags.NONE);
        var sb = new StringBuilder.sized (bytes.get_size () + 1);
        sb.append_len ((string) bytes.get_data (), (ssize_t) bytes.get_size ());
        this.from_text (sb.str);
    }

    public EmojiStore.from_text (string data) throws Error {
        emojis = new GenericArray<Emoji> ();
        by_text = new HashTable<string, Emoji> (str_hash, str_equal);

        int lineno = 0;
        foreach (unowned string line in data.split ("\n")) {
            lineno++;
            if (line.length == 0) {
                continue;
            }
            string[] f = line.split ("\t");
            if (f.length != 6) {
                throw new IOError.INVALID_DATA ("emoji data line %d: expected 6 fields, got %d",
                                                lineno, f.length);
            }
            var e = new Emoji ();
            e.index = emojis.length;
            e.group = int.parse (f[0]);
            if (e.group < 0 || e.group >= GROUP_TITLES.length) {
                throw new IOError.INVALID_DATA ("emoji data line %d: bad group %s", lineno, f[0]);
            }
            e.text = f[1];
            e.name = f[2];
            e.keywords = f[3].length > 0 ? f[3].split ("|") : new string[0];
            e.variants = f[4].length > 0 ? f[4].split (",") : new string[0];
            e.renderable_variants = e.variants;
            e.version = f[5];

            e.norm_name = TextUtil.normalize (e.name);
            e.norm_name_words = e.norm_name.split (" ");
            e.norm_keywords = new string[e.keywords.length];
            for (int i = 0; i < e.keywords.length; i++) {
                e.norm_keywords[i] = TextUtil.normalize (e.keywords[i]);
            }

            emojis.add (e);
            by_text.insert (e.text, e);
            foreach (unowned string v in e.variants) {
                by_text.insert (v, e);
            }
        }

        if (emojis.length == 0) {
            throw new IOError.INVALID_DATA ("emoji data is empty");
        }
    }

    /* Returns the base emoji for a base or skin-tone variant string. */
    public Emoji? lookup (string text) {
        return by_text.lookup (text);
    }
}
