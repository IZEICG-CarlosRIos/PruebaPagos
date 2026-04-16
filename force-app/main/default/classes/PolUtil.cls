public class PolUtil {
    private static final Integer MAX_LONG_TEXT_LENGTH = 32768;

    public static String buildPgsWrapper(String data0, String encryptedB64) {
        return
            '<pgs><data0>' +
            escapeXml(data0) +
            '</data0><data>' +
            escapeXml(encryptedB64) +
            '</data></pgs>';
    }

    public static String extractTag(String xml, String tagName) {
        if (String.isBlank(xml) || String.isBlank(tagName)) {
            return null;
        }

        String regex = '(?i)<' + tagName + '>([\\s\\S]*?)</' + tagName + '>';
        Matcher m = Pattern.compile(regex).matcher(xml);

        if (m.find()) {
            return m.group(1).trim();
        }

        return null;
    }

    public static String extractFirstUrl(String text) {
        if (String.isBlank(text)) {
            return null;
        }

        Matcher m = Pattern.compile('(https?://[^\\s<"\\]]+)').matcher(text);
        return m.find() ? m.group(1) : null;
    }

    public static String escapeXml(String s) {
        if (s == null) {
            return '';
        }

        return s
            .replace('&', '&amp;')
            .replace('<', '&lt;')
            .replace('>', '&gt;')
            .replace('"', '&quot;')
            .replace('\'', '&apos;');
    }

    public static String joinLines(List<String> lines) {
        if (lines == null || lines.isEmpty()) {
            return '';
        }
        return String.join(lines, '\n');
    }

    public static String appendAudit(String currentLog, String entry) {
        if (String.isBlank(entry)) {
            return currentLog;
        }

        String timestamp = Datetime.now().formatGmt('yyyy-MM-dd HH:mm:ss') + 'Z';
        String stamped = '[' + timestamp + '] ' + entry;

        if (String.isBlank(currentLog)) {
            return trimToMax(stamped, MAX_LONG_TEXT_LENGTH);
        }

        return trimToMax(currentLog + '\n\n' + stamped, MAX_LONG_TEXT_LENGTH);
    }

    public static String trimToMax(String value, Integer maxLen) {
        if (value == null) {
            return null;
        }
        if (maxLen == null || value.length() <= maxLen) {
            return value;
        }
        return value.substring(value.length() - maxLen);
    }
}
