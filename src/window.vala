namespace Comprime {

    [GtkTemplate (ui = "/fr/benjaminbellamy/comprime/ui/window.ui")]
    public class Window : Adw.ApplicationWindow {

        [GtkChild] private unowned Gtk.Button open_button;
        [GtkChild] private unowned Gtk.Stack stack;
        [GtkChild] private unowned Adw.ComboRow quality_row;
        [GtkChild] private unowned Adw.PreferencesGroup files_group;
        [GtkChild] private unowned Gtk.ActionBar action_bar;
        [GtkChild] private unowned Gtk.Button compress_button;
        [GtkChild] private unowned Gtk.Button cancel_button;

        private GLib.Settings settings;
        private GenericArray<FileRow> rows = new GenericArray<FileRow> ();

        private bool encoding = false;
        private bool batch_cancelled = false;
        private Encoder? current_encoder = null;

        public Window (Application app) {
            Object (application: app);
        }

        construct {
            settings = new GLib.Settings (APP_ID);
            settings.bind ("window-width", this, "default-width", SettingsBindFlags.DEFAULT);
            settings.bind ("window-height", this, "default-height", SettingsBindFlags.DEFAULT);

            quality_row.selected = (uint) settings.get_enum ("quality");
            quality_row.notify["selected"].connect (() => {
                settings.set_enum ("quality", (int) quality_row.selected);
            });

            var open_action = new SimpleAction ("open", null);
            open_action.activate.connect (open_files_dialog);
            add_action (open_action);

            var compress_action = new SimpleAction ("compress", null);
            compress_action.activate.connect (() => { start_queue.begin (); });
            add_action (compress_action);

            var cancel_action = new SimpleAction ("cancel", null);
            cancel_action.activate.connect (cancel_queue);
            add_action (cancel_action);

            setup_drop_target ();
            update_state ();
        }

        private void setup_drop_target () {
            var drop = new Gtk.DropTarget (typeof (Gdk.FileList), Gdk.DragAction.COPY);
            drop.drop.connect ((value, x, y) => {
                var file_list = (Gdk.FileList) value.get_boxed ();
                if (file_list == null) {
                    return false;
                }
                File[] files = {};
                foreach (unowned File file in file_list.get_files ()) {
                    files += file;
                }
                add_files (files);
                return true;
            });
            ((Gtk.Widget) this).add_controller (drop);
        }

        private void open_files_dialog () {
            var dialog = new Gtk.FileDialog () {
                title = "Open Video Files",
                modal = true
            };

            var filter = new Gtk.FileFilter () { name = "Video files" };
            filter.add_mime_type ("video/*");
            var filters = new ListStore (typeof (Gtk.FileFilter));
            filters.append (filter);
            dialog.filters = filters;
            dialog.default_filter = filter;

            dialog.open_multiple.begin (this, null, (obj, res) => {
                try {
                    var model = dialog.open_multiple.end (res);
                    File[] files = {};
                    for (uint i = 0; i < model.get_n_items (); i++) {
                        files += (File) model.get_item (i);
                    }
                    add_files (files);
                } catch (Error e) {
                    // dialog dismissed
                }
            });
        }

        public void add_files (File[] files) {
            if (encoding) {
                return;
            }
            foreach (var file in files) {
                if (file == null || contains_file (file)) {
                    continue;
                }
                var row = new FileRow (file);
                row.remove_requested.connect (remove_row);
                rows.add (row);
                files_group.add (row.row);
            }
            update_state ();
        }

        private bool contains_file (File file) {
            for (int i = 0; i < rows.length; i++) {
                if (rows[i].file.equal (file)) {
                    return true;
                }
            }
            return false;
        }

        private void remove_row (FileRow row) {
            if (encoding) {
                return;
            }
            files_group.remove (row.row);
            rows.remove (row);
            update_state ();
        }

        private void update_state () {
            bool has_files = rows.length > 0;
            stack.visible_child_name = has_files ? "files" : "empty";
            action_bar.revealed = has_files;

            open_button.sensitive = !encoding;
            quality_row.sensitive = !encoding;
            compress_button.visible = !encoding;
            compress_button.sensitive = has_files && !encoding;
            cancel_button.visible = encoding;
        }

        private async void start_queue () {
            if (encoding || rows.length == 0) {
                return;
            }
            encoding = true;
            batch_cancelled = false;
            update_state ();

            var quality = (Quality) quality_row.selected;

            for (int i = 0; i < rows.length && !batch_cancelled; i++) {
                var row = rows[i];
                if (row.state == FileRow.State.DONE) {
                    continue;
                }

                var output = Encoder.output_for (row.file);
                row.set_encoding ();

                current_encoder = new Encoder (row.file, output, quality);
                current_encoder.progress.connect (row.set_progress);

                bool ok = false;
                try {
                    ok = yield current_encoder.run ();
                } catch (Error e) {
                    row.set_failed (e.message);
                    current_encoder = null;
                    continue;
                }
                current_encoder = null;

                if (batch_cancelled) {
                    row.set_cancelled ();
                    break;
                }
                if (ok) {
                    row.set_done (output);
                } else {
                    row.set_failed ("ffmpeg reported an error");
                }
            }

            encoding = false;
            current_encoder = null;
            update_state ();
        }

        private void cancel_queue () {
            if (!encoding) {
                return;
            }
            batch_cancelled = true;
            if (current_encoder != null) {
                current_encoder.cancel ();
            }
        }
    }

    /** A single file entry rendered as an AdwActionRow with progress and status. */
    private class FileRow : Object {

        public enum State { READY, ENCODING, DONE, FAILED, CANCELLED }

        public signal void remove_requested (FileRow row);

        public File file { get; construct; }
        public Adw.ActionRow row { get; private set; }
        public State state { get; private set; default = State.READY; }

        private Gtk.ProgressBar bar;
        private Gtk.Button remove_button;
        private Gtk.Image status_icon;
        private Timer? timer;

        public FileRow (File file) {
            Object (file: file);
        }

        construct {
            row = new Adw.ActionRow () {
                title = file.get_basename (),
                subtitle = "Ready",
                title_lines = 1
            };

            bar = new Gtk.ProgressBar () {
                valign = Gtk.Align.CENTER,
                width_request = 120,
                visible = false
            };
            row.add_suffix (bar);

            status_icon = new Gtk.Image () {
                valign = Gtk.Align.CENTER,
                visible = false
            };
            row.add_suffix (status_icon);

            remove_button = new Gtk.Button () {
                icon_name = "edit-delete-symbolic",
                valign = Gtk.Align.CENTER,
                tooltip_text = "Remove from list"
            };
            remove_button.add_css_class ("flat");
            remove_button.clicked.connect (() => remove_requested (this));
            row.add_suffix (remove_button);
        }

        public void set_progress (double fraction) {
            bar.visible = true;
            double elapsed = timer != null ? timer.elapsed () : 0;
            if (fraction < 0) {
                bar.pulse ();
                row.subtitle = "Encoding… · %s elapsed".printf (format_duration (elapsed));
                return;
            }
            bar.fraction = fraction;
            int percent = (int) (fraction * 100 + 0.5);
            if (fraction > 0.01) {
                double remaining = elapsed * (1.0 - fraction) / fraction;
                var eta = new DateTime.now_local ().add_seconds (remaining);
                row.subtitle = "%d%% · %s elapsed · done ~%s".printf (
                    percent, format_duration (elapsed), eta.format ("%Hh%M"));
            } else {
                row.subtitle = "%d%% · %s elapsed".printf (percent, format_duration (elapsed));
            }
        }

        public void set_encoding () {
            state = State.ENCODING;
            timer = new Timer ();
            row.subtitle = "Starting…";
            bar.fraction = 0;
            bar.visible = true;
            status_icon.visible = false;
            remove_button.visible = false;
        }

        public void set_done (File output) {
            state = State.DONE;
            double took = timer != null ? timer.elapsed () : 0;
            row.subtitle = "Done in %s · %s".printf (format_duration (took), output.get_basename ());
            bar.visible = false;
            show_status ("emblem-ok-symbolic", "success");
        }

        /** Formats a duration in seconds as M:SS or H:MM:SS. */
        private static string format_duration (double seconds) {
            int total = (int) (seconds + 0.5);
            int h = total / 3600;
            int m = (total % 3600) / 60;
            int s = total % 60;
            if (h > 0) {
                return "%d:%02d:%02d".printf (h, m, s);
            }
            return "%d:%02d".printf (m, s);
        }

        public void set_failed (string message) {
            state = State.FAILED;
            row.subtitle = "Failed · " + message;
            bar.visible = false;
            show_status ("dialog-error-symbolic", "error");
            remove_button.visible = true;
        }

        public void set_cancelled () {
            state = State.CANCELLED;
            row.subtitle = "Cancelled";
            bar.visible = false;
            remove_button.visible = true;
        }

        private void show_status (string icon_name, string css_class) {
            status_icon.icon_name = icon_name;
            status_icon.remove_css_class ("success");
            status_icon.remove_css_class ("error");
            status_icon.add_css_class (css_class);
            status_icon.visible = true;
        }
    }
}
