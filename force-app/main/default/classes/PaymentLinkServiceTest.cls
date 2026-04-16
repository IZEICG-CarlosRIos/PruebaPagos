@IsTest
private class PaymentLinkServiceTest {
    private static final String PAYMENT_URL = 'https://sandboxpol.mit.com.mx/pay/test-token';
    private static Integer retryThenSuccessCallCount = 0;

    private class SuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setStatus('OK');

            String payload =
                '<response>' +
                '<url>' +
                PAYMENT_URL +
                '</url>' +
                '<id_transaccion>TXN-001</id_transaccion>' +
                '</response>';

            String encrypted = PolCrypto.encryptB64(payload, getAesKeyHex());
            res.setBody('<pgs><data>' + encrypted + '</data></pgs>');
            return res;
        }
    }

    private class RetryThenSuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            retryThenSuccessCallCount++;

            HttpResponse res = new HttpResponse();
            if (retryThenSuccessCallCount == 1) {
                res.setStatusCode(503);
                res.setStatus('Service Unavailable');
                res.setBody('temporarily unavailable');
                return res;
            }

            res.setStatusCode(200);
            res.setStatus('OK');
            String payload = '<response><url>' + PAYMENT_URL + '</url></response>';
            String encrypted = PolCrypto.encryptB64(payload, getAesKeyHex());
            res.setBody('<pgs><data>' + encrypted + '</data></pgs>');
            return res;
        }
    }

    private class AlwaysServerErrorMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(503);
            res.setStatus('Service Unavailable');
            res.setBody('temporarily unavailable');
            return res;
        }
    }

    @IsTest
    static void generateLink_success() {
        Payment_Link__c payment = createPaymentLink('REF-SUCCESS-001');

        PaymentLinkService.maxRetriesOverride = 0;
        PaymentLinkService.timeoutOverrideMs = 5000;
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        Test.startTest();
        Payment_Link__c result = PaymentLinkService.generateLink(payment.Id);
        Test.stopTest();

        Payment_Link__c stored = [
            SELECT Status__c, Payment_URL__c, Attempt_Count__c, Provider_Transaction_ID__c, Raw_Request__c, Raw_Response__c
            FROM Payment_Link__c
            WHERE Id = :payment.Id
        ];

        System.assertEquals('Pending', stored.Status__c);
        System.assertEquals(PAYMENT_URL, stored.Payment_URL__c);
        System.assertEquals(1, Integer.valueOf(String.valueOf(stored.Attempt_Count__c)));
        System.assertEquals('TXN-001', stored.Provider_Transaction_ID__c);
        System.assertNotEquals(null, stored.Raw_Request__c);
        System.assert(stored.Raw_Response__c.contains(PAYMENT_URL));
        System.assertEquals(stored.Id, result.Id);

        clearOverrides();
    }

    @IsTest
    static void generateLink_retriesThenSuccess() {
        Payment_Link__c payment = createPaymentLink('REF-RETRY-001');

        PaymentLinkService.maxRetriesOverride = 2;
        PaymentLinkService.timeoutOverrideMs = 5000;
        retryThenSuccessCallCount = 0;
        Test.setMock(HttpCalloutMock.class, new RetryThenSuccessMock());

        Test.startTest();
        PaymentLinkService.generateLink(payment.Id);
        Test.stopTest();

        Payment_Link__c stored = [
            SELECT Status__c, Attempt_Count__c, Raw_Response__c
            FROM Payment_Link__c
            WHERE Id = :payment.Id
        ];

        System.assertEquals('Pending', stored.Status__c);
        System.assertEquals(2, Integer.valueOf(String.valueOf(stored.Attempt_Count__c)));
        System.assert(stored.Raw_Response__c.contains('Intento 1: HTTP 503'));
        System.assert(stored.Raw_Response__c.contains('Intento 2: HTTP 200'));

        clearOverrides();
    }

    @IsTest
    static void generateLink_failsAfterRetries() {
        Payment_Link__c payment = createPaymentLink('REF-ERROR-001');

        PaymentLinkService.maxRetriesOverride = 2;
        PaymentLinkService.timeoutOverrideMs = 5000;
        Test.setMock(HttpCalloutMock.class, new AlwaysServerErrorMock());

        Boolean failed = false;

        Test.startTest();
        try {
            PaymentLinkService.generateLink(payment.Id);
        } catch (AuraHandledException e) {
            failed = true;
        }
        Test.stopTest();

        System.assertEquals(true, failed);

        Payment_Link__c stored = [
            SELECT Status__c, Attempt_Count__c, Raw_Response__c
            FROM Payment_Link__c
            WHERE Id = :payment.Id
        ];

        System.assertEquals('Error', stored.Status__c);
        System.assertEquals(3, Integer.valueOf(String.valueOf(stored.Attempt_Count__c)));
        System.assert(stored.Raw_Response__c.contains('HTTP 503'));

        clearOverrides();
    }

    @IsTest
    static void generateLink_includesConfiguredMetadataAndPersistsRows() {
        Payment_Link__c payment = createPaymentLink('REF-META-001');
        payment.Workspace__c = 'WS-META';
        payment.Metadata_JSON__c =
            '{"producto":"Laptop","unidades":2,"entrega":"2026-03-25","fiscal":true}';
        update payment;

        PaymentLinkMetadataService.definitionOverrides = new List<PaymentLinkMetadataService.FieldDefinition>{
            new PaymentLinkMetadataService.FieldDefinition(
                'producto',
                'Producto',
                'Text',
                true,
                true,
                'producto',
                10,
                'WS-META'
            ),
            new PaymentLinkMetadataService.FieldDefinition(
                'unidades',
                'Unidades',
                'Number',
                false,
                true,
                'unidades',
                20,
                'WS-META'
            ),
            new PaymentLinkMetadataService.FieldDefinition(
                'entrega',
                'Fecha de Entrega',
                'Date',
                false,
                true,
                'entrega',
                30,
                'WS-META'
            ),
            new PaymentLinkMetadataService.FieldDefinition(
                'fiscal',
                'Factura',
                'Boolean',
                false,
                true,
                'fiscal',
                40,
                'WS-META'
            )
        };

        PaymentLinkService.maxRetriesOverride = 0;
        PaymentLinkService.timeoutOverrideMs = 5000;
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        Test.startTest();
        PaymentLinkService.generateLink(payment.Id);
        Test.stopTest();

        Payment_Link__c stored = [
            SELECT Raw_Request__c, Metadata_JSON__c, Metadata_Index__c, Status__c
            FROM Payment_Link__c
            WHERE Id = :payment.Id
        ];

        System.assertEquals('Pending', stored.Status__c);
        String encryptedPayload = PolUtil.extractTag(stored.Raw_Request__c, 'data');
        String decryptedRequest = PolCrypto.decryptB64(encryptedPayload, getAesKeyHex());
        System.assert(decryptedRequest.contains('<metadata>'));
        System.assert(decryptedRequest.contains('<producto>Laptop</producto>'));
        System.assert(decryptedRequest.contains('<unidades>2</unidades>'));
        System.assert(decryptedRequest.contains('<entrega>2026-03-25</entrega>'));
        System.assert(decryptedRequest.contains('<fiscal>true</fiscal>'));
        System.assert(stored.Metadata_JSON__c.contains('"producto":"Laptop"'));
        System.assert(stored.Metadata_Index__c.contains('producto=Laptop'));

        List<Payment_Link_Metadata__c> metadataRows = [
            SELECT Field_API_Name__c, Value_Text__c, Value_Number__c, Value_Date__c, Value_Boolean__c
            FROM Payment_Link_Metadata__c
            WHERE Payment_Link__c = :payment.Id
            ORDER BY Field_API_Name__c
        ];

        System.assertEquals(4, metadataRows.size());

        clearOverrides();
    }

    @IsTest
    static void generateLink_failsWhenRequiredMetadataIsMissing() {
        Payment_Link__c payment = createPaymentLink('REF-META-REQ-001');
        payment.Workspace__c = 'WS-REQ';
        payment.Metadata_JSON__c = '{"canal":"W"}';
        update payment;

        PaymentLinkMetadataService.definitionOverrides = new List<PaymentLinkMetadataService.FieldDefinition>{
            new PaymentLinkMetadataService.FieldDefinition(
                'producto',
                'Producto',
                'Text',
                true,
                true,
                'producto',
                10,
                'WS-REQ'
            )
        };

        Boolean failed = false;

        Test.startTest();
        try {
            PaymentLinkService.generateLink(payment.Id);
        } catch (AuraHandledException e) {
            failed = true;
        }
        Test.stopTest();

        System.assertEquals(true, failed);

        clearOverrides();
    }

    @IsTest
    static void generateLink_usesPaymentCurrencyWhenProvided() {
        Payment_Link__c payment = createPaymentLink('REF-CURRENCY-001');
        payment.Currency__c = 'USD';
        update payment;

        PaymentLinkService.maxRetriesOverride = 0;
        PaymentLinkService.timeoutOverrideMs = 5000;
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        Test.startTest();
        PaymentLinkService.generateLink(payment.Id);
        Test.stopTest();

        Payment_Link__c stored = [
            SELECT Raw_Request__c
            FROM Payment_Link__c
            WHERE Id = :payment.Id
        ];

        String encryptedPayload = PolUtil.extractTag(stored.Raw_Request__c, 'data');
        String decryptedRequest = PolCrypto.decryptB64(encryptedPayload, getAesKeyHex());
        System.assert(decryptedRequest.contains('<moneda>USD</moneda>'));

        clearOverrides();
    }

    private static Payment_Link__c createPaymentLink(String reference) {
        Payment_Link__c payment = new Payment_Link__c(
            Amount__c = 100,
            Reference__c = reference,
            Concept__c = 'Prueba',
            Customer_Name__c = 'cliente@correo.com',
            Status__c = 'Draft'
        );
        insert payment;
        return payment;
    }

    private static String getAesKeyHex() {
        PagosOnline_Config__mdt cfg = PagosOnline_Config__mdt.getInstance('ConfiguracionPrueba');
        System.assertNotEquals(null, cfg, 'Se requiere metadata ConfiguracionPrueba para pruebas.');
        System.assert(!String.isBlank(cfg.AESKeyHex__c), 'AESKeyHex__c no configurado.');
        return cfg.AESKeyHex__c;
    }

    private static void clearOverrides() {
        PaymentLinkService.maxRetriesOverride = null;
        PaymentLinkService.timeoutOverrideMs = null;
        PaymentLinkService.configNameOverride = null;
        PaymentLinkMetadataService.definitionOverrides = null;
    }
}
