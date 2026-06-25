namespace Comprime {

    /**
     * Encoding quality levels.
     *
     * The base ffmpeg parameters use constant-quality encoding (-crf 20) with a
     * 192k audio track. Any level other than DEFAULT switches the video stream to
     * a target bitrate (ABR, dropping -crf) and overrides the audio bitrate.
     */
    public enum Quality {
        DEFAULT,
        HIGH,
        MEDIUM,
        LOW,
        EXTRA_LOW;

        public string display_name () {
            switch (this) {
                case DEFAULT:   return "Default";
                case HIGH:      return "High quality";
                case MEDIUM:    return "Medium quality";
                case LOW:       return "Low quality";
                case EXTRA_LOW: return "Extra low quality";
                default:        return "Default";
            }
        }

        /** GSettings enum nick for this level. */
        public string nick () {
            switch (this) {
                case DEFAULT:   return "default";
                case HIGH:      return "high";
                case MEDIUM:    return "medium";
                case LOW:       return "low";
                case EXTRA_LOW: return "extra-low";
                default:        return "default";
            }
        }

        public static Quality from_nick (string nick) {
            switch (nick) {
                case "high":      return HIGH;
                case "medium":    return MEDIUM;
                case "low":       return LOW;
                case "extra-low": return EXTRA_LOW;
                default:          return DEFAULT;
            }
        }

        /**
         * Target video bitrate, or null to keep constant-quality (-crf) encoding.
         */
        public string? video_bitrate () {
            switch (this) {
                case HIGH:      return "8M";
                case MEDIUM:    return "4M";
                case LOW:       return "2M";
                case EXTRA_LOW: return "1M";
                default:        return null;
            }
        }

        /** Audio bitrate; overrides the base -b:a 192k. */
        public string audio_bitrate () {
            switch (this) {
                case HIGH:      return "256k";
                case MEDIUM:    return "192k";
                case LOW:       return "128k";
                case EXTRA_LOW: return "96k";
                default:        return "192k";
            }
        }
    }
}
