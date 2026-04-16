public class PolCrypto {
    private static final String AES_ALGORITHM = 'AES128';

    public static String encryptB64(String plaintext, String keyHex) {
        Blob encryptedPayload = Crypto.encryptWithManagedIV(
            AES_ALGORITHM,
            toAesKey(keyHex),
            Blob.valueOf(plaintext)
        );
        return EncodingUtil.base64Encode(encryptedPayload);
    }

    public static String decryptB64(String b64, String keyHex) {
        Blob encryptedPayload = EncodingUtil.base64Decode(b64);
        Blob plaintext = Crypto.decryptWithManagedIV(
            AES_ALGORITHM,
            toAesKey(keyHex),
            encryptedPayload
        );
        return plaintext.toString();
    }

    private static Blob toAesKey(String keyHex) {
        return EncodingUtil.convertFromHex(keyHex);
    }
}
