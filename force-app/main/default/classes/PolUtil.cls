public class PolUtil {
    public static String buildPgsWrapper(String data0, String encryptedB64) {
        return '<pgs><data0>' + escapeXml(data0) + '</data0><data>' + escapeXml(encryptedB64) + '</data></pgs>';
    }

    public static String extractTag(String xml, String tagName) {
        if (String.isBlank(xml) || String.isBlank(tagName)) {
            return null;
        }
    
        String regex = '(?i)<' + tagName + '>([\\s\\S]*?)</' + tagName + '>';
    
        Pattern p = Pattern.compile(regex);
        Matcher m = p.matcher(xml);
    
        if (m.find()) {
            return m.group(1).trim();
        }
    
        return null;
	}

    public static String extractFirstUrl(String text) {
        if (String.isBlank(text)) return null;

        Matcher m = Pattern.compile('(https?://[^\\s<"\\]]+)').matcher(text);
        return m.find() ? m.group(1) : null;
    }

    public static String escapeXml(String s) {
        if (s == null) return '';
        return s.replace('&','&amp;')
                .replace('<','&lt;')
                .replace('>','&gt;')
                .replace('"','&quot;')
                .replace('\'','&apos;');
    }
}