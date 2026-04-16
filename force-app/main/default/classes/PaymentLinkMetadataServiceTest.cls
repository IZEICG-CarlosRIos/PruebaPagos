@IsTest
private class PaymentLinkMetadataServiceTest {
    @IsTest
    static void saveMetadata_successfullyNormalizesAndPersists() {
        Payment_Link__c payment = new Payment_Link__c(
            Amount__c = 125,
            Reference__c = 'REF-META-SAVE-001',
            Concept__c = 'Prueba Metadata',
            Customer_Name__c = 'cliente@correo.com',
            Workspace__c = 'WS-SAVE',
            Status__c = 'Draft'
        );
        insert payment;

        PaymentLinkMetadataService.definitionOverrides = new List<PaymentLinkMetadataService.FieldDefinition>{
            new PaymentLinkMetadataService.FieldDefinition('producto', 'Producto', 'Text', true, true, 'producto', 10, 'WS-SAVE'),
            new PaymentLinkMetadataService.FieldDefinition('piezas', 'Piezas', 'Number', false, true, 'piezas', 20, 'WS-SAVE'),
            new PaymentLinkMetadataService.FieldDefinition('entrega', 'Entrega', 'Date', false, true, 'entrega', 30, 'WS-SAVE'),
            new PaymentLinkMetadataService.FieldDefinition('fiscal', 'Fiscal', 'Boolean', false, true, 'fiscal', 40, 'WS-SAVE')
        };

        String metadataJson = '{"producto":"Mouse","piezas":"3","entrega":"25/03/2026","fiscal":"yes"}';

        Test.startTest();
        PaymentLinkMetadataService.SaveMetadataResultDto result = PaymentLinkMetadataService.saveMetadata(payment.Id, metadataJson);
        Test.stopTest();

        Payment_Link__c storedPayment = [
            SELECT Metadata_JSON__c, Metadata_Index__c
            FROM Payment_Link__c
            WHERE Id = :payment.Id
        ];

        System.assertEquals(payment.Id, result.paymentLinkId);
        System.assertEquals('WS-SAVE', result.workspace);
        System.assert(storedPayment.Metadata_JSON__c.contains('"producto":"Mouse"'));
        System.assert(storedPayment.Metadata_JSON__c.contains('"piezas":3'));
        System.assert(storedPayment.Metadata_JSON__c.contains('"entrega":"2026-03-25"'));
        System.assert(storedPayment.Metadata_JSON__c.contains('"fiscal":true'));
        System.assert(storedPayment.Metadata_Index__c.contains('producto=Mouse'));

        List<Payment_Link_Metadata__c> rows = [
            SELECT Field_API_Name__c, Value_Text__c, Value_Number__c, Value_Date__c, Value_Boolean__c
            FROM Payment_Link_Metadata__c
            WHERE Payment_Link__c = :payment.Id
        ];
        System.assertEquals(4, rows.size());

        PaymentLinkMetadataService.definitionOverrides = null;
    }

    @IsTest
    static void saveMetadata_rejectsUnknownField() {
        Payment_Link__c payment = new Payment_Link__c(
            Amount__c = 125,
            Reference__c = 'REF-META-UNK-001',
            Concept__c = 'Prueba Metadata',
            Customer_Name__c = 'cliente@correo.com',
            Workspace__c = 'WS-UNK',
            Status__c = 'Draft'
        );
        insert payment;

        PaymentLinkMetadataService.definitionOverrides = new List<PaymentLinkMetadataService.FieldDefinition>{
            new PaymentLinkMetadataService.FieldDefinition('producto', 'Producto', 'Text', false, true, 'producto', 10, 'WS-UNK')
        };

        Boolean failed = false;

        Test.startTest();
        try {
            PaymentLinkMetadataService.saveMetadata(payment.Id, '{"otroCampo":"valor"}');
        } catch (AuraHandledException e) {
            failed = true;
        }
        Test.stopTest();

        System.assertEquals(true, failed);

        PaymentLinkMetadataService.definitionOverrides = null;
    }

    @IsTest
    static void saveMetadata_rejectsInvalidJson() {
        Payment_Link__c payment = new Payment_Link__c(
            Amount__c = 125,
            Reference__c = 'REF-META-JSON-001',
            Concept__c = 'Prueba Metadata',
            Customer_Name__c = 'cliente@correo.com',
            Workspace__c = 'WS-JSON',
            Status__c = 'Draft'
        );
        insert payment;

        Boolean failed = false;

        Test.startTest();
        try {
            PaymentLinkMetadataService.saveMetadata(payment.Id, 'esto no es json');
        } catch (AuraHandledException e) {
            failed = true;
        }
        Test.stopTest();

        System.assertEquals(true, failed);
    }
}
