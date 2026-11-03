int main (string[] args) {
    Environment.set_prgname ("emozi");
    Environment.set_application_name ("Emozi");
    /* libatspi warns when another app advertises a stale accessibility
     * socket, then falls back to the bus by itself. Drop that noise. (The
     * handler must not log itself: nested logging aborts in GLib.) */
    Log.set_handler ("dbind", LogLevelFlags.LEVEL_WARNING, () => {});
    return new Emozi.Application ().run (args);
}
