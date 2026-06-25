namespace Comprime {

    /**
     * Re-encodes a single video file with ffmpeg.
     *
     * The base parameters match the project specification; quality levels other
     * than DEFAULT switch the video stream to a target bitrate and override audio.
     */
    public class Encoder : Object {

        public File input { get; construct; }
        public File output { get; construct; }
        public Quality quality { get; construct; }

        /** Encoding progress as a fraction in [0, 1]; -1 means indeterminate. */
        public signal void progress (double fraction);

        private Subprocess? process;
        private Cancellable cancellable = new Cancellable ();
        private double duration_secs = 0;
        private int64 src_video_bps = 0; // 0 = unknown
        private int64 src_audio_bps = 0; // 0 = unknown

        public Encoder (File input, File output, Quality quality) {
            Object (input: input, output: output, quality: quality);
        }

        /** Builds the output File: original name with "_reencoded" before the extension. */
        public static File output_for (File input) {
            string basename = input.get_basename ();
            int dot = basename.last_index_of_char ('.');
            string name, ext;
            if (dot > 0) {
                name = basename.substring (0, dot);
                ext = basename.substring (dot);
            } else {
                name = basename;
                ext = "";
            }
            return input.get_parent ().get_child (name + "_reencoded" + ext);
        }

        public void cancel () {
            cancellable.cancel ();
            if (process != null) {
                process.send_signal (15); // SIGTERM
            }
        }

        public async bool run () throws Error {
            yield probe_source ();

            process = new Subprocess.newv (
                build_argv (),
                SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE
            );

            progress (duration_secs > 0 ? 0.0 : -1.0);

            // Drain ffmpeg's progress output to EOF first, then reap the process.
            // Reading fully before waiting keeps this a single sequential flow and
            // avoids racing the child's teardown against an in-flight pipe read.
            var stream = new DataInputStream (process.get_stdout_pipe ());
            try {
                string? line;
                while ((line = yield stream.read_line_async (Priority.DEFAULT, cancellable)) != null) {
                    parse_progress (line);
                }
            } catch (Error e) {
                // stream closed or cancelled; fall through to wait for the exit status
            }

            yield process.wait_async (cancellable);

            if (cancellable.is_cancelled ()) {
                // Remove the partial output so a cancelled job leaves nothing behind.
                try {
                    yield output.delete_async (Priority.DEFAULT, null);
                } catch (Error e) {
                    // nothing to clean up
                }
                return false;
            }

            return process.get_successful ();
        }

        private string[] build_argv () {
            // Use a plain Vala string[] (NULL-terminated by Vala) so it is safe to
            // hand to g_subprocess_newv, which expects a NULL-terminated argv.
            string[] argv = { "ffmpeg", "-y", "-i", input.get_path () };

            // Video.
            argv += "-c:v"; argv += "libx264";
            argv += "-profile:v"; argv += "high";
            argv += "-level"; argv += "4.0";
            argv += "-preset"; argv += "slow";

            // Apply the quality's target video bitrate only if it would actually
            // shrink the stream; otherwise keep constant-quality (-crf) encoding so
            // we never upscale a low-bitrate source.
            string? vbr = quality.video_bitrate ();
            if (vbr != null && (src_video_bps == 0 || parse_bitrate (vbr) < src_video_bps)) {
                argv += "-b:v"; argv += vbr;
            } else {
                argv += "-crf"; argv += "20";
            }

            argv += "-pix_fmt"; argv += "yuv420p";

            // Audio: never encode above the source bitrate (upscaling lossy audio
            // only wastes space), so cap the chosen bitrate at the source's.
            int64 abr_bps = parse_bitrate (quality.audio_bitrate ());
            if (src_audio_bps > 0 && src_audio_bps < abr_bps) {
                abr_bps = src_audio_bps;
            }
            argv += "-c:a"; argv += "aac";
            argv += "-b:a"; argv += (abr_bps / 1000).to_string () + "k";
            argv += "-ar"; argv += "48000";
            argv += "-ac"; argv += "2";

            argv += "-movflags"; argv += "+faststart";

            // Machine-readable progress on stdout.
            argv += "-progress"; argv += "pipe:1";
            argv += "-nostats";

            argv += output.get_path ();
            return argv;
        }

        private void parse_progress (string line) {
            if (duration_secs <= 0) {
                return;
            }
            if (line.has_prefix ("out_time_us=")) {
                string val = line.substring ("out_time_us=".length).strip ();
                int64 us;
                if (int64.try_parse (val, out us) && us > 0) {
                    double frac = (us / 1000000.0) / duration_secs;
                    progress (frac.clamp (0.0, 1.0));
                }
            }
        }

        // Probes the source for its duration (drives the progress bar) and its
        // per-stream bitrates (used to skip quality overrides that would only
        // upscale the file). Missing values stay at 0 = unknown.
        private async void probe_source () {
            try {
                var probe = new Subprocess.newv (
                    {
                        "ffprobe", "-v", "quiet",
                        "-show_entries", "format=duration:stream=codec_type,bit_rate",
                        "-of", "default=noprint_wrappers=0:nokey=0",
                        input.get_path ()
                    },
                    SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE
                );
                string? stdout_buf;
                yield probe.communicate_utf8_async (null, cancellable, out stdout_buf, null);
                if (stdout_buf == null) {
                    return;
                }

                string current_type = "";
                foreach (string raw in stdout_buf.split ("\n")) {
                    string line = raw.strip ();
                    if (line.has_prefix ("codec_type=")) {
                        current_type = line.substring ("codec_type=".length);
                    } else if (line.has_prefix ("bit_rate=")) {
                        int64 br;
                        if (int64.try_parse (line.substring ("bit_rate=".length), out br) && br > 0) {
                            if (current_type == "video") {
                                src_video_bps = br;
                            } else if (current_type == "audio") {
                                src_audio_bps = br;
                            }
                        }
                    } else if (line.has_prefix ("duration=")) {
                        double secs;
                        if (double.try_parse (line.substring ("duration=".length), out secs) && secs > 0) {
                            duration_secs = secs;
                        }
                    }
                }
            } catch (Error e) {
                // fall through with whatever was parsed
            }
        }

        /** Parses an ffmpeg bitrate string like "8M" or "256k" into bits per second. */
        private static int64 parse_bitrate (string spec) {
            string s = spec.strip ();
            double mult = 1;
            if (s.has_suffix ("M") || s.has_suffix ("m")) {
                mult = 1000000;
                s = s.substring (0, s.length - 1);
            } else if (s.has_suffix ("k") || s.has_suffix ("K")) {
                mult = 1000;
                s = s.substring (0, s.length - 1);
            }
            double val;
            if (double.try_parse (s, out val) && val > 0) {
                return (int64) (val * mult);
            }
            return 0;
        }
    }
}
