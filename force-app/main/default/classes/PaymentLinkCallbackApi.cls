@RestResource(urlMapping='/pagosonline/callback/*')
global without sharing class PaymentLinkCallbackApi {
    private static final String DEFAULT_CONFIG_NAME = 'ConfiguracionPrueba';

    @HttpPost
    global static void receive() {
        ensureJsonResponse();

        try {
            RestRequest req = RestContext.request;
            String rawBody = req == null || req.requestBody == null ? '' : req.requestBody.toString();
            String normalizedPayload = normalizePayload(rawBody, req);
            Map<String, String> values = extractValues(normalizedPayload);

            String reference = resolveReference(values);

            if (String.isBlank(reference)) {
                setResponse(400, false, 'Referencia no encontrada en callback.', null);
                return;
            }

            Payment_Link__c link = findPaymentLink(reference);
            if (link == null) {
                setResponse(404, false, 'No existe referencia ' + reference + '.', null);
                return;
            }

            String providerStatusRaw = resolveProviderStatusRaw(values);
            String mappedStatus = mapProviderStatus(providerStatusRaw);
            String providerTransactionId = resolveProviderTransactionId(values);
            applyCallbackToPaymentLink(
                link,
                reference,
                providerStatusRaw,
                mappedStatus,
                providerTransactionId,
                rawBody,
                normalizedPayload
            );

            setResponse(200, true, 'Callback procesado.', mappedStatus);
        } catch (Exception e) {
            setResponse(500, false, 'Error procesando callback: ' + e.getMessage(), null);
        }
    }

    private static RestResponse ensureJsonResponse() {
        RestResponse response = RestContext.response;
        if (response == null) {
            response = new RestResponse();
            RestContext.response = response;
        }
        response.addHeader('Content-Type', 'application/json');
        return response;
    }

    private static String resolveReference(Map<String, String> values) {
        return firstNonBlank(
            new List<String>{
                values.get('reference'),
                values.get('referencia'),
                values.get('nb_referencia'),
                values.get('id_referencia'),
                values.get('orderid'),
                values.get('folio')
            }
        );
    }

    private static String resolveProviderStatusRaw(Map<String, String> values) {
        return firstNonBlank(
            new List<String>{
                values.get('status'),
                values.get('estatus'),
                values.get('result'),
                values.get('resultado'),
                values.get('response_code'),
                values.get('response')
            }
        );
    }

    private static String resolveProviderTransactionId(Map<String, String> values) {
        return firstNonBlank(
            new List<String>{
                values.get('id_transaccion'),
                values.get('idtransaccion'),
                values.get('transaction_id'),
                values.get('transactionid'),
                values.get('id_operacion'),
                values.get('idoperacion'),
                values.get('auth')
            }
        );
    }

    private static Payment_Link__c findPaymentLink(String reference) {
        List<Payment_Link__c> links = [
            SELECT
                Id,
                Reference__c,
                Status__c,
                Provider_Transaction_ID__c,
                Raw_Response__c
            FROM Payment_Link__c
            WHERE Reference__c = :reference
            LIMIT 1
        ];
        return links.isEmpty() ? null : links[0];
    }

    private static void applyCallbackToPaymentLink(
        Payment_Link__c link,
        String reference,
        String providerStatusRaw,
        String mappedStatus,
        String providerTransactionId,
        String rawBody,
        String normalizedPayload
    ) {
        if (!String.isBlank(providerTransactionId)) {
            link.Provider_Transaction_ID__c = providerTransactionId;
        }
        link.Status__c = mappedStatus;
        link.Raw_Response__c = PolUtil.appendAudit(
            link.Raw_Response__c,
            buildAuditEntry(reference, providerStatusRaw, mappedStatus, rawBody, normalizedPayload)
        );
        update link;
    }

    @TestVisible
    private static String normalizePayload(String rawBody, RestRequest req) {
        String payload = rawBody;

        if (String.isBlank(payload) && req != null && req.params != null) {
            if (!String.isBlank(req.params.get('xml'))) {
                payload = req.params.get('xml');
            } else if (!String.isBlank(req.params.get('data'))) {
                payload = req.params.get('data');
            }
        }

        if (!String.isBlank(payload) && payload.startsWith('xml=')) {
            payload = EncodingUtil.urlDecode(payload.substring(4), 'UTF-8');
        }

        if (!String.isBlank(payload) && payload.contains('&') && payload.contains('=')) {
            Map<String, String> queryValues = parseQueryString(payload);
            if (!String.isBlank(queryValues.get('xml'))) {
                payload = queryValues.get('xml');
            } else if (!String.isBlank(queryValues.get('data'))) {
                payload = queryValues.get('data');
            }
        }

        return tryDecryptPayload(payload);
    }

    @TestVisible
    private static String tryDecryptPayload(String payload) {
        if (String.isBlank(payload)) {
            return payload;
        }

        String encryptedB64 = PolUtil.extractTag(payload, 'data');
        if (String.isBlank(encryptedB64) && isLikelyBase64(payload)) {
            encryptedB64 = payload.trim();
        }
        if (String.isBlank(encryptedB64)) {
            return payload;
        }

        PagosOnline_Config__mdt cfg = PagosOnline_Config__mdt.getInstance(DEFAULT_CONFIG_NAME);
        if (cfg == null || String.isBlank(cfg.AESKeyHex__c)) {
            return payload;
        }

        try {
            return PolCrypto.decryptB64(encryptedB64, cfg.AESKeyHex__c);
        } catch (Exception e) {
            return payload;
        }
    }

    @TestVisible
    private static Map<String, String> extractValues(String payload) {
        Map<String, String> values = new Map<String, String>();
        if (String.isBlank(payload)) {
            return values;
        }

        Matcher xmlMatcher = Pattern.compile('(?is)<([a-zA-Z0-9_\\-]+)>([^<]*)</\\1>').matcher(payload);
        while (xmlMatcher.find()) {
            String key = xmlMatcher.group(1);
            String value = xmlMatcher.group(2);
            if (String.isBlank(key) || String.isBlank(value)) {
                continue;
            }
            values.put(key.toLowerCase(), value.trim());
        }

        if (payload.contains('=')) {
            Map<String, String> queryValues = parseQueryString(payload);
            for (String key : queryValues.keySet()) {
                values.put(key.toLowerCase(), queryValues.get(key));
            }
        }

        return values;
    }

    @TestVisible
    private static Map<String, String> parseQueryString(String raw) {
        Map<String, String> parsed = new Map<String, String>();
        if (String.isBlank(raw)) {
            return parsed;
        }

        for (String pair : raw.split('&')) {
            if (String.isBlank(pair)) {
                continue;
            }

            Integer idx = pair.indexOf('=');
            String key;
            String value;

            if (idx < 0) {
                key = EncodingUtil.urlDecode(pair, 'UTF-8');
                value = '';
            } else {
                key = EncodingUtil.urlDecode(pair.substring(0, idx), 'UTF-8');
                value = EncodingUtil.urlDecode(pair.substring(idx + 1), 'UTF-8');
            }

            if (!String.isBlank(key)) {
                parsed.put(key, value);
            }
        }

        return parsed;
    }

    private static String firstNonBlank(List<String> values) {
        if (values == null) {
            return null;
        }

        for (String value : values) {
            if (!String.isBlank(value)) {
                return value.trim();
            }
        }

        return null;
    }

    @TestVisible
    private static String mapProviderStatus(String rawStatus) {
        String token = normalizeToken(rawStatus);
        if (String.isBlank(token)) {
            return 'Pending';
        }

        if (
            token == '00' ||
            token == '0' ||
            token == 'ok' ||
            token == 'success' ||
            token.contains('approved') ||
            token.contains('aprobado') ||
            token.contains('autorizado') ||
            token.contains('pagado') ||
            token.contains('paid')
        ) {
            return 'Approved';
        }

        if (
            token.contains('expired') ||
            token.contains('expirado') ||
            token.contains('vencido') ||
            token.contains('timeout')
        ) {
            return 'Expired';
        }

        if (
            token == '05' ||
            token == '51' ||
            token.contains('rejected') ||
            token.contains('rechazado') ||
            token.contains('declined') ||
            token.contains('denied') ||
            token.contains('failed') ||
            token.contains('error') ||
            token.contains('cancel')
        ) {
            return 'Rejected';
        }

        return 'Pending';
    }

    private static String normalizeToken(String value) {
        if (String.isBlank(value)) {
            return null;
        }

        return value
            .toLowerCase()
            .replace(' ', '')
            .replace('_', '')
            .replace('-', '')
            .trim();
    }

    private static Boolean isLikelyBase64(String payload) {
        if (String.isBlank(payload)) {
            return false;
        }

        String trimmed = payload.trim();
        if (trimmed.contains('<') || trimmed.contains('&')) {
            return false;
        }

        return Pattern.compile('^[A-Za-z0-9+/=\\r\\n]+$').matcher(trimmed).matches();
    }

    private static String buildAuditEntry(
        String reference,
        String providerStatusRaw,
        String mappedStatus,
        String rawBody,
        String normalizedPayload
    ) {
        List<String> lines = new List<String>();
        lines.add('Callback recibido para referencia ' + reference + '.');
        lines.add('Estatus proveedor: ' + (String.isBlank(providerStatusRaw) ? '(vacio)' : providerStatusRaw));
        lines.add('Estatus interno: ' + mappedStatus + '.');

        if (!String.isBlank(rawBody)) {
            lines.add('Raw: ' + PolUtil.trimToMax(rawBody, 1400));
        }

        if (!String.isBlank(normalizedPayload) && normalizedPayload != rawBody) {
            lines.add('Normalizado: ' + PolUtil.trimToMax(normalizedPayload, 1400));
        }

        return String.join(lines, '\n');
    }

    private static void setResponse(Integer statusCode, Boolean success, String message, String status) {
        RestResponse res = RestContext.response;
        if (res == null) {
            res = new RestResponse();
            RestContext.response = res;
        }

        Map<String, Object> body = new Map<String, Object>{
            'success' => success,
            'message' => message
        };
        if (!String.isBlank(status)) {
            body.put('status', status);
        }

        res.statusCode = statusCode;
        res.responseBody = Blob.valueOf(JSON.serialize(body));
    }
}
