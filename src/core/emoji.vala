namespace Emozi {
    /* Section ids: 0..8 are Unicode groups (see GROUP_TITLES); FREQUENT is ours. */
    public const int SECTION_FREQUENT = -1;
    public const int SECTION_SEARCH = -2;

    public const string[] GROUP_TITLES = {
        "Smileys & Emotion",
        "People & Body",
        "Animals & Nature",
        "Food & Drink",
        "Travel & Places",
        "Activities",
        "Objects",
        "Symbols",
        "Flags"
    };

    /* Symbolic icons shipped inside GTK 3 itself (used by GtkEmojiChooser),
     * so they exist on every system and follow the theme's foreground color. */
    public const string[] GROUP_ICONS = {
        "emoji-people-symbolic",
        "emoji-body-symbolic",
        "emoji-nature-symbolic",
        "emoji-food-symbolic",
        "emoji-travel-symbolic",
        "emoji-activities-symbolic",
        "emoji-objects-symbolic",
        "emoji-symbols-symbolic",
        "emoji-flags-symbolic"
    };

    /* Fallback glyphs for the category bar if an icon is missing. */
    public const string[] GROUP_GLYPHS = {
        "😀", "👋", "🐻", "🍔", "✈️", "⚽", "💡", "🔣", "🏳️"
    };

    public const string FREQUENT_TITLE = "Frequently Used";
    public const string FREQUENT_ICON = "emoji-recent-symbolic";
    public const string FREQUENT_GLYPH = "🕘";

    public class Emoji {
        public int index;
        public int group;
        public string text;
        public string name;
        public string[] keywords;
        /* Skin-tone variants, in Unicode order (5 for one person, 25 for two). */
        public string[] variants;
        public string version;

        /* Filled by Coverage: can the system font draw it as a single glyph? */
        public bool renderable = true;
        /* Subset of `variants` the font can draw. */
        public string[] renderable_variants;

        /* Pre-normalized search fields. */
        public string norm_name;
        public string[] norm_name_words;
        public string[] norm_keywords;

        public bool has_variants {
            get { return renderable_variants.length > 0; }
        }

        /* A tone-specific variant (1..5 → light..dark), or null. Two-person
         * emojis use the same tone for both people. */
        public string? variant_for_tone (int tone) {
            if (tone < 1 || tone > 5) {
                return null;
            }
            if (variants.length == 5) {
                return variants[tone - 1];
            }
            if (variants.length == 25) {
                int i = (tone - 1) * 5 + (tone - 1);
                return variants[i];
            }
            return null;
        }

        public bool is_variant (string s) {
            foreach (unowned string v in variants) {
                if (v == s) {
                    return true;
                }
            }
            return false;
        }

        /* "smiling face with heart-eyes" → "Smiling face with heart-eyes" */
        public string display_name {
            owned get {
                if (name.length == 0) {
                    return name;
                }
                unichar c = name.get_char (0);
                return c.toupper ().to_string () + name.substring (c.to_string ().length);
            }
        }

        /* ":smiling_face_with_heart_eyes:" */
        public string shortcode {
            owned get {
                var sb = new StringBuilder (":");
                bool sep = false;
                unichar c;
                int i = 0;
                while (norm_name.get_next_char (ref i, out c)) {
                    if (c.isalnum ()) {
                        if (sep && sb.len > 1) {
                            sb.append_c ('_');
                        }
                        sb.append_unichar (c);
                        sep = false;
                    } else {
                        sep = true;
                    }
                }
                sb.append_c (':');
                return sb.str;
            }
        }
    }

    namespace TextUtil {
        /* Case-fold, strip accents, and turn punctuation into single spaces so
         * "Flag: Côte d’Ivoire" and "flag cote d ivoire" compare equal. */
        public string normalize (string s) {
            string decomposed = s.casefold ().normalize (-1, NormalizeMode.NFD);
            var sb = new StringBuilder ();
            bool pending_space = false;
            unichar c;
            int i = 0;
            while (decomposed.get_next_char (ref i, out c)) {
                UnicodeType t = c.type ();
                if (t == UnicodeType.NON_SPACING_MARK) {
                    continue;
                }
                if (c.isalnum () || c == '+' || c == '#' || c == '*' ||
                    t == UnicodeType.OTHER_SYMBOL) {
                    if (pending_space && sb.len > 0) {
                        sb.append_c (' ');
                    }
                    pending_space = false;
                    sb.append_unichar (c);
                } else if (c == '-' && sb.len > 0 && !pending_space) {
                    /* keep intra-word hyphens: "t-rex", "x-ray" */
                    sb.append_c ('-');
                } else {
                    pending_space = true;
                }
            }
            return sb.str;
        }

        /* Codepoints as "1F600-200D-..." — safe as a GKeyFile key. */
        public string to_key (string emoji) {
            var sb = new StringBuilder ();
            unichar c;
            int i = 0;
            while (emoji.get_next_char (ref i, out c)) {
                if (sb.len > 0) {
                    sb.append_c ('-');
                }
                sb.append_printf ("%04X", (uint) c);
            }
            return sb.str;
        }
    }
}
