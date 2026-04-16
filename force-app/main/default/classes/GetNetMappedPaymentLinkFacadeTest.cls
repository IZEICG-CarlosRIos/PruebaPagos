@IsTest
private class GetNetMappedPaymentLinkFacadeTest {
    private static final String BASE_URL = 'https://sandboxpol.mit.com.mx/pay/';

    private class SuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setStatus('OK');

            String payload =
                '<response>' +
                '<url>' +
                BASE_URL +
                'token-test</url>' +
                '<id_transaccion>TXN-MAPPED-001</id_transaccion>' +
                '</response>';
            String encrypted = PolCrypto.encryptB64(payload, getAesKeyHex());
            res.setBody('<pgs><data>' + encrypted + '</data></pgs>');
            return res;
        }
    }

    @IsTest
    static void getMappedRecordContext_prefillsFromMappedRecord() {
        Opportunity opp = createOpportunity('OPP-MAPPED-CONTEXT', 123.45);

        GetNetMappedPaymentLinkFacade.setTestMappingOverride(
            'Opportunity',
            'Name',
            'Amount',
            'MXN',
            'ConfiguracionPrueba'
        );

        Test.startTest();
        GetNetMappedPaymentLinkFacade.MappedRecordContextDto contextDto =
            GetNetMappedPaymentLinkFacade.getMappedRecordContext(opp.Id, 'Opportunity', null);
        Test.stopTest();

        System.assertEquals(opp.Id, contextDto.recordId);
        System.assertEquals('Opportunity', contextDto.objectApiName);
        System.assertEquals('Name', contextDto.referenceField);
        System.assertEquals('Amount', contextDto.amountField);
        System.assertEquals('OPP-MAPPED-CONTEXT', contextDto.reference);
        System.assertEquals(123.45, contextDto.amount);
        System.assertEquals('MXN', contextDto.currencyCode);
        System.assertEquals('ConfiguracionPrueba', contextDto.workspace);
        System.assertEquals(false, contextDto.hasExistingLink);

        GetNetMappedPaymentLinkFacade.clearTestMappingOverrides();
    }

    @IsTest
    static void getMappedRecordContext_withoutMapping_throwsException() {
        Opportunity opp = createOpportunity('OPP-NO-MAPPING', 50);
        GetNetMappedPaymentLinkFacade.useEmptyTestMappingOverrides();

        Boolean failed = false;

        Test.startTest();
        try {
            GetNetMappedPaymentLinkFacade.getMappedRecordContext(opp.Id, 'Opportunity', null);
        } catch (AuraHandledException e) {
            failed = true;
            System.assert(!String.isBlank(e.getMessage()));
        }
        Test.stopTest();

        System.assertEquals(true, failed);
        GetNetMappedPaymentLinkFacade.clearTestMappingOverrides();
    }

    @IsTest
    static void getMappedRecordContext_usesWorkspaceSpecificMapping() {
        Opportunity opp = createOpportunity('OPP-MAPPED-WS', 80);

        GetNetMappedPaymentLinkFacade.setTestMappingOverride(
            'Opportunity',
            'Name',
            'Amount',
            'MXN',
            'WS_A'
        );
        GetNetMappedPaymentLinkFacade.setTestMappingOverride(
            'Opportunity',
            'Name',
            'Amount',
            'USD',
            'WS_B'
        );

        Test.startTest();
        GetNetMappedPaymentLinkFacade.MappedRecordContextDto contextDto =
            GetNetMappedPaymentLinkFacade.getMappedRecordContext(opp.Id, 'Opportunity', 'WS_B');
        Test.stopTest();

        System.assertEquals('USD', contextDto.currencyCode);
        System.assertEquals('WS_B', contextDto.workspace);

        GetNetMappedPaymentLinkFacade.clearTestMappingOverrides();
    }

    @IsTest
    static void generateFromMappedRecord_createsPaymentLinkAndGeneratesUrl() {
        Opportunity opp = createOpportunity('OPP-MAPPED-GEN', 349.99);
        GetNetMappedPaymentLinkFacade.setTestMappingOverride(
            'Opportunity',
            'Name',
            'Amount',
            'USD',
            'ConfiguracionPrueba'
        );
        PaymentLinkMetadataService.definitionOverrides = new List<PaymentLinkMetadataService.FieldDefinition>{
            new PaymentLinkMetadataService.FieldDefinition(
                'canal',
                'Canal',
                'Text',
                true,
                true,
                'canal',
                10,
                'ConfiguracionPrueba'
            ),
            new PaymentLinkMetadataService.FieldDefinition(
                'producto',
                'Producto',
                'Text',
                false,
                true,
                'producto',
                20,
                'ConfiguracionPrueba'
            )
        };
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        GetNetMappedPaymentLinkFacade.GenerateMappedPaymentLinkRequestDto request =
            new GetNetMappedPaymentLinkFacade.GenerateMappedPaymentLinkRequestDto();
        request.recordId = opp.Id;
        request.objectApiName = 'Opportunity';
        request.reference = 'REF-MAPPED-' + String.valueOf(System.now().getTime());
        request.amount = 349.99;
        request.currencyCode = 'USD';
        request.concept = 'Mapped Payment Link';
        request.customerName = 'cliente@correo.com';
        request.workspace = 'ConfiguracionPrueba';
        request.metadataJson = '{"canal":"W","producto":"Mouse"}';

        Test.startTest();
        GetNetMappedPaymentLinkFacade.GenerateMappedPaymentLinkResultDto result =
            GetNetMappedPaymentLinkFacade.generateFromMappedRecord(request);
        Test.stopTest();

        System.assertNotEquals(null, result.paymentLinkId);
        System.assertEquals(false, result.wasExisting);
        System.assertEquals('Pending', result.status);
        System.assert(result.paymentUrl != null && result.paymentUrl.startsWith(BASE_URL));
        System.assertEquals('USD', result.currencyCode);

        Payment_Link__c stored = [
            SELECT
                Reference__c,
                Amount__c,
                Currency__c,
                Workspace__c,
                Concept__c,
                Customer_Name__c,
                Payment_URL__c,
                Metadata_JSON__c,
                Metadata_Index__c,
                Status__c
            FROM Payment_Link__c
            WHERE Id = :result.paymentLinkId
            LIMIT 1
        ];

        System.assertEquals(request.reference, stored.Reference__c);
        System.assertEquals(request.amount, stored.Amount__c);
        System.assertEquals('USD', stored.Currency__c);
        System.assertEquals('ConfiguracionPrueba', stored.Workspace__c);
        System.assertEquals('Mapped Payment Link', stored.Concept__c);
        System.assertEquals('cliente@correo.com', stored.Customer_Name__c);
        System.assert(!String.isBlank(stored.Payment_URL__c));
        System.assert(stored.Metadata_JSON__c.contains('"canal":"W"'));
        System.assert(stored.Metadata_Index__c.contains('canal=W'));
        System.assertEquals('Pending', stored.Status__c);

        List<Payment_Link_Metadata__c> metadataRows = [
            SELECT Id
            FROM Payment_Link_Metadata__c
            WHERE Payment_Link__c = :result.paymentLinkId
        ];
        System.assert(metadataRows.size() > 0, 'Debe persistir detalle metadata.');

        GetNetMappedPaymentLinkFacade.clearTestMappingOverrides();
        PaymentLinkMetadataService.definitionOverrides = null;
    }

    @IsTest
    static void generateFromMappedRecord_updatesExistingPaymentLinkByReference() {
        Opportunity opp = createOpportunity('OPP-MAPPED-UPDATE', 100);
        GetNetMappedPaymentLinkFacade.setTestMappingOverride(
            'Opportunity',
            'Name',
            'Amount',
            'MXN',
            'ConfiguracionPrueba'
        );
        PaymentLinkMetadataService.definitionOverrides = new List<PaymentLinkMetadataService.FieldDefinition>{
            new PaymentLinkMetadataService.FieldDefinition(
                'canal',
                'Canal',
                'Text',
                true,
                true,
                'canal',
                10,
                'ConfiguracionPrueba'
            ),
            new PaymentLinkMetadataService.FieldDefinition(
                'producto',
                'Producto',
                'Text',
                false,
                true,
                'producto',
                20,
                'ConfiguracionPrueba'
            )
        };
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        String reference = 'REF-EXISTING-' + String.valueOf(System.now().getTime());
        Payment_Link__c existing = new Payment_Link__c(
            Reference__c = reference,
            Amount__c = 10,
            Currency__c = 'MXN',
            Workspace__c = 'ConfiguracionPrueba',
            Concept__c = 'Concepto viejo',
            Customer_Name__c = 'viejo@correo.com',
            Metadata_JSON__c = '{"canal":"W"}',
            Status__c = 'Draft'
        );
        insert existing;

        GetNetMappedPaymentLinkFacade.GenerateMappedPaymentLinkRequestDto request =
            new GetNetMappedPaymentLinkFacade.GenerateMappedPaymentLinkRequestDto();
        request.recordId = opp.Id;
        request.objectApiName = 'Opportunity';
        request.reference = reference;
        request.amount = 777;
        request.currencyCode = 'MXN';
        request.concept = 'Concepto nuevo';
        request.customerName = 'nuevo@correo.com';
        request.workspace = 'ConfiguracionPrueba';
        request.metadataJson = '{"canal":"W","producto":"Laptop"}';

        Test.startTest();
        GetNetMappedPaymentLinkFacade.GenerateMappedPaymentLinkResultDto result =
            GetNetMappedPaymentLinkFacade.generateFromMappedRecord(request);
        Test.stopTest();

        System.assertEquals(true, result.wasExisting);
        System.assertEquals(existing.Id, result.paymentLinkId);

        Payment_Link__c stored = [
            SELECT
                Id,
                Amount__c,
                Concept__c,
                Customer_Name__c,
                Status__c,
                Payment_URL__c,
                Metadata_JSON__c
            FROM Payment_Link__c
            WHERE Id = :existing.Id
            LIMIT 1
        ];

        System.assertEquals(777, stored.Amount__c);
        System.assertEquals('Concepto nuevo', stored.Concept__c);
        System.assertEquals('nuevo@correo.com', stored.Customer_Name__c);
        System.assertEquals('Pending', stored.Status__c);
        System.assert(!String.isBlank(stored.Payment_URL__c));
        System.assert(stored.Metadata_JSON__c.contains('"producto":"Laptop"'));

        GetNetMappedPaymentLinkFacade.clearTestMappingOverrides();
        PaymentLinkMetadataService.definitionOverrides = null;
    }

    private static Opportunity createOpportunity(String name, Decimal amount) {
        Opportunity opp = new Opportunity(
            Name = name,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(7),
            Amount = amount
        );
        insert opp;
        return opp;
    }

    private static String getAesKeyHex() {
        PagosOnline_Config__mdt cfg = PagosOnline_Config__mdt.getInstance('ConfiguracionPrueba');
        System.assertNotEquals(null, cfg, 'Debe existir ConfiguracionPrueba para pruebas.');
        System.assert(!String.isBlank(cfg.AESKeyHex__c), 'AESKeyHex__c no puede estar vacio en pruebas.');
        return cfg.AESKeyHex__c;
    }
}
