@IsTest
private class PaymentLinkCallbackApiTest {
    @IsTest
    static void receive_plainApproved_updatesPaymentLink() {
        Payment_Link__c payment = createPaymentLink('REF-CB-APPROVED');
        String body =
            '<callback>' +
            '<reference>REF-CB-APPROVED</reference>' +
            '<status>APPROVED</status>' +
            '<id_transaccion>TXN-CB-001</id_transaccion>' +
            '</callback>';

        invokeCallback(body);

        Payment_Link__c stored = [
            SELECT Status__c, Provider_Transaction_ID__c, Raw_Response__c
            FROM Payment_Link__c
            WHERE Id = :payment.Id
        ];

        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('Approved', stored.Status__c);
        System.assertEquals('TXN-CB-001', stored.Provider_Transaction_ID__c);
        System.assert(stored.Raw_Response__c.contains('Callback recibido'));
    }

    @IsTest
    static void receive_encryptedRejected_updatesPaymentLink() {
        Payment_Link__c payment = createPaymentLink('REF-CB-REJECTED');

        String payload =
            '<callback>' +
            '<reference>REF-CB-REJECTED</reference>' +
            '<estatus>RECHAZADO</estatus>' +
            '<id_transaccion>TXN-CB-002</id_transaccion>' +
            '</callback>';
        String encrypted = PolCrypto.encryptB64(payload, getAesKeyHex());
        String body = '<pgs><data>' + encrypted + '</data></pgs>';

        invokeCallback(body);

        Payment_Link__c stored = [
            SELECT Status__c, Provider_Transaction_ID__c
            FROM Payment_Link__c
            WHERE Id = :payment.Id
        ];

        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('Rejected', stored.Status__c);
        System.assertEquals('TXN-CB-002', stored.Provider_Transaction_ID__c);
    }

    @IsTest
    static void receive_missingReference_returns400() {
        String body = '<callback><status>APPROVED</status></callback>';

        invokeCallback(body);

        System.assertEquals(400, RestContext.response.statusCode);
        Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
        System.assertEquals(false, responseBody.get('success'));
    }

    @IsTest
    static void receive_unknownReference_returns404() {
        String body = '<callback><reference>NO-EXISTE</reference><status>APPROVED</status></callback>';

        invokeCallback(body);

        System.assertEquals(404, RestContext.response.statusCode);
    }

    private static void invokeCallback(String body) {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/pagosonline/callback';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(body);

        RestContext.request = req;
        RestContext.response = new RestResponse();

        PaymentLinkCallbackApi.receive();
    }

    private static Payment_Link__c createPaymentLink(String reference) {
        Payment_Link__c payment = new Payment_Link__c(
            Amount__c = 100,
            Reference__c = reference,
            Concept__c = 'Prueba callback',
            Customer_Name__c = 'cliente@correo.com',
            Status__c = 'Pending'
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
}
