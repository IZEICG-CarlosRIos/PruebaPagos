public class PolCrypto {
    public static String encryptB64(String plaintext, String keyHex) {
        Blob key = EncodingUtil.convertFromHex(keyHex);
        Blob out = Crypto.encryptWithManagedIV('AES128', key, Blob.valueOf(plaintext));
        return EncodingUtil.base64Encode(out);
    }

    public static String decryptB64(String b64, String keyHex) {
        Blob key = EncodingUtil.convertFromHex(keyHex);
        Blob raw = EncodingUtil.base64Decode(b64);
        Blob plain = Crypto.decryptWithManagedIV('AES128', key, raw);
        return plain.toString();
    }
}