namespace Comprime {

    public const string APP_ID = "fr.benjaminbellamy.comprime";
    public const string VERSION = "1.0.0";

    public class Application : Adw.Application {

        public Application () {
            Object (
                application_id: APP_ID,
                flags: ApplicationFlags.HANDLES_OPEN
            );
        }

        construct {
            ActionEntry[] actions = {
                { "about", on_about },
                { "quit", on_quit },
            };
            add_action_entries (actions, this);
            set_accels_for_action ("app.quit", { "<primary>q" });
            set_accels_for_action ("win.open", { "<primary>o" });
        }

        private Window get_main_window () {
            var window = active_window as Window;
            if (window == null) {
                window = new Window (this);
            }
            return window;
        }

        public override void activate () {
            get_main_window ().present ();
        }

        public override void open (File[] files, string hint) {
            var window = get_main_window ();
            window.add_files (files);
            window.present ();
        }

        private void on_quit () {
            quit ();
        }

        private void on_about () {
            var about = new Adw.AboutDialog () {
                application_name = "comprimé",
                application_icon = APP_ID,
                developer_name = "Benjamin Bellamy",
                version = VERSION,
                license_type = Gtk.License.GPL_3_0,
                comments = "Compress and re-encode video files with ffmpeg."
            };
            about.present (active_window);
        }
    }
}
