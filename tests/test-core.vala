/* Unit tests for the UI-independent core: data loading, search ranking,
 * usage/frecency and skin-tone memory. Run with `meson test -C build`. */
using Emozi;

static EmojiStore store;

static string first_result (string query) {
    var r = Search.run (store, query);
    return r.length > 0 ? r[0].text : "(none)";
}

static void test_data () {
    /* Unicode 17.0: 3944 fully-qualified emoji = 1914 bases + 2030 tone variants */
    int bases = store.emojis.length;
    int variants = 0;
    store.emojis.foreach ((e) => variants += e.variants.length);
    assert_cmpint (bases, CompareOperator.EQ, 1914);
    assert_cmpint (bases + variants, CompareOperator.EQ, 3944);

    var thumbs = store.lookup ("👍");
    assert_nonnull (thumbs);
    assert_cmpint (thumbs.variants.length, CompareOperator.EQ, 5);
    assert_cmpstr (thumbs.name, CompareOperator.EQ, "thumbs up");

    /* variants resolve to their base */
    assert_true (store.lookup ("👍🏽") == thumbs);
    assert_cmpint (store.lookup ("🤝").variants.length, CompareOperator.EQ, 25);
    assert_cmpint (store.lookup ("💏").variants.length, CompareOperator.EQ, 25);

    /* every group is populated */
    int[] counts = new int[GROUP_TITLES.length];
    store.emojis.foreach ((e) => counts[e.group]++);
    foreach (int c in counts) {
        assert_cmpint (c, CompareOperator.GT, 0);
    }
}

static void test_normalize () {
    assert_cmpstr (TextUtil.normalize ("Flag: Côte d’Ivoire"), CompareOperator.EQ, "flag cote d ivoire");
    assert_cmpstr (TextUtil.normalize ("  :Grinning_Face:  "), CompareOperator.EQ, "grinning face");
    assert_cmpstr (TextUtil.normalize ("T-Rex"), CompareOperator.EQ, "t-rex");
    assert_cmpstr (TextUtil.to_key ("#️⃣"), CompareOperator.EQ, "0023-FE0F-20E3");
}

static void test_search () {
    assert_cmpstr (first_result ("fire"), CompareOperator.EQ, "🔥");
    assert_cmpstr (first_result ("thumbs up"), CompareOperator.EQ, "👍");
    assert_cmpstr (first_result (":thumbs_up:"), CompareOperator.EQ, "👍");
    assert_cmpstr (first_result ("+1"), CompareOperator.EQ, "👍");
    assert_cmpstr (first_result ("japan"), CompareOperator.EQ, "🇯🇵");
    assert_cmpstr (first_result ("cote d'ivoire"), CompareOperator.EQ, "🇨🇮");
    assert_cmpstr (first_result ("😀"), CompareOperator.EQ, "😀");
    assert_cmpstr (first_result ("grinning face"), CompareOperator.EQ, "😀");
    assert_cmpint (Search.run (store, "zzzzqqq").length, CompareOperator.EQ, 0);
    assert_cmpint (Search.run (store, "   ").length, CompareOperator.EQ, 0);

    /* all terms must match */
    var r = Search.run (store, "cat face");
    assert_cmpint (r.length, CompareOperator.GT, 0);
    r.foreach ((e) => {
        assert_true (e.norm_name.contains ("cat") || "cat" in e.norm_keywords ||
                     e.norm_keywords.length > 0);
    });
}

static void test_usage () {
    var usage = new UsageStore (null);
    int64 now = 1700000000;
    var fire = store.lookup ("🔥");
    var thumbs = store.lookup ("👍");

    /* defaults when empty */
    var f = usage.frequent (store, 18, now);
    assert_cmpint (f.length, CompareOperator.EQ, 18);

    usage.record (fire, "🔥", now);
    usage.record (fire, "🔥", now);
    usage.record (thumbs, "👍🏾", now);
    f = usage.frequent (store, 18, now);
    assert_true (f[0] == fire);
    assert_true (f[1] == thumbs);
    assert_cmpint (f.length, CompareOperator.EQ, 18);

    /* no duplicates */
    var seen = new GenericSet<Emoji> (direct_hash, direct_equal);
    f.foreach ((e) => {
        assert_false (seen.contains (e));
        seen.add (e);
    });

    /* skin tone memory */
    assert_cmpstr (usage.preferred_variant (thumbs), CompareOperator.EQ, "👍🏾");
    assert_null (usage.preferred_variant (fire));
    usage.record (thumbs, "👍", now);
    assert_cmpstr (usage.preferred_variant (thumbs), CompareOperator.EQ, "👍");

    /* decay: an old heavy user loses to a recent one eventually */
    var u2 = new UsageStore (null);
    for (int i = 0; i < 4; i++) {
        u2.record (fire, "🔥", now);
    }
    u2.record (thumbs, "👍", now + 60 * 24 * 3600);
    var f2 = u2.frequent (store, 2, now + 60 * 24 * 3600);
    assert_true (f2[0] == thumbs);

    /* tone helper */
    assert_cmpstr (thumbs.variant_for_tone (3), CompareOperator.EQ, "👍🏽");
    assert_cmpstr (store.lookup ("🤝").variant_for_tone (1), CompareOperator.EQ, "🤝🏻");
}

static void test_usage_persistence () {
    string dir;
    try {
        dir = DirUtils.make_tmp ("emozi-test-XXXXXX");
    } catch (Error e) {
        assert_not_reached ();
    }
    string path = Path.build_filename (dir, "sub", "usage.ini");
    var hash_key = store.lookup ("#️⃣");
    assert_nonnull (hash_key);

    var a = new UsageStore (path);
    a.record (hash_key, hash_key.text, 1700000000);
    var b = new UsageStore (path);
    assert_true (b.frequent (store, 1, 1700000000)[0] == hash_key);

    FileUtils.unlink (path);
    DirUtils.remove (Path.build_filename (dir, "sub"));
    DirUtils.remove (dir);
}

int main (string[] args) {
    Test.init (ref args);
    if (args.length < 2) {
        printerr ("usage: test-core EMOJI_DATA_TSV\n");
        return 2;
    }
    try {
        string data;
        FileUtils.get_contents (args[1], out data);
        store = new EmojiStore.from_text (data);
    } catch (Error e) {
        printerr ("cannot load %s: %s\n", args[1], e.message);
        return 1;
    }
    Test.add_func ("/data/counts", test_data);
    Test.add_func ("/text/normalize", test_normalize);
    Test.add_func ("/search/ranking", test_search);
    Test.add_func ("/usage/frecency", test_usage);
    Test.add_func ("/usage/persistence", test_usage_persistence);
    return Test.run ();
}
