@IsTest
private class GetNetPaymentUiFacadeTest {
    @IsTest
    static void getAuthorizationConfig_returnsDefaultConfigValues() {
        Test.startTest();
        GetNetPaymentUiFacade.AuthorizationConfigDto response = GetNetPaymentUiFacade.getAuthorizationConfig(null);
        Test.stopTest();

        System.assertEquals('ConfiguracionPrueba', response.configName);
        System.assertNotEquals(null, response.companyId, 'CompanyId debe venir de custom metadata.');
        System.assertNotEquals(null, response.branchId, 'BranchId debe venir de custom metadata.');
        System.assertNotEquals(null, response.user, 'User debe venir de custom metadata.');
        System.assertNotEquals(null, response.password, 'Password debe venir de custom metadata.');
        System.assertNotEquals(null, response.encryptionKey, 'AES key debe venir de custom metadata.');
        System.assertNotEquals(null, response.data0, 'Data0 debe venir de custom metadata.');
    }

    @IsTest
    static void saveAuthorizationConfig_validRequest_returnsSuccessInTestMode() {
        GetNetPaymentUiFacade.AuthorizationConfigDto request = new GetNetPaymentUiFacade.AuthorizationConfigDto();
        request.configName = 'ConfiguracionPrueba';
        request.companyId = 'NEWCO';
        request.branchId = 'BR001';
        request.user = 'USR001';
        request.password = 'PASS001';
        request.encryptionKey = 'ABCDEF1234567890ABCDEF1234567890';
        request.data0 = 'DATA0';

        Test.startTest();
        GetNetPaymentUiFacade.SaveAuthorizationResultDto result = GetNetPaymentUiFacade.saveAuthorizationConfig(request);
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assertEquals('ConfiguracionPrueba', result.configName);
        System.assertEquals('Simulated', result.deploymentStatus);
    }

    @IsTest
    static void saveAuthorizationConfigDirect_validRequest_returnsSuccessInTestMode() {
        Test.startTest();
        GetNetPaymentUiFacade.SaveAuthorizationResultDto result = GetNetPaymentUiFacade.saveAuthorizationConfigDirect(
            'ConfiguracionPrueba',
            'NEWCO',
            'BR001',
            'USR001',
            'PASS001',
            'ABCDEF1234567890ABCDEF1234567890',
            'DATA0'
        );
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assertEquals('ConfiguracionPrueba', result.configName);
        System.assertEquals('Simulated', result.deploymentStatus);
    }

    @IsTest
    static void saveAuthorizationConfig_missingRequired_throwsException() {
        GetNetPaymentUiFacade.AuthorizationConfigDto request = new GetNetPaymentUiFacade.AuthorizationConfigDto();
        request.configName = 'ConfiguracionPrueba';
        request.companyId = '';
        request.branchId = 'BR001';
        request.user = 'USR001';
        request.password = 'PASS001';
        request.encryptionKey = 'ABCDEF1234567890ABCDEF1234567890';
        request.data0 = 'DATA0';

        Boolean failed = false;
        Test.startTest();
        try {
            GetNetPaymentUiFacade.saveAuthorizationConfig(request);
        } catch (AuraHandledException e) {
            failed = true;
            System.assert(!String.isBlank(e.getMessage()));
        }
        Test.stopTest();

        System.assertEquals(true, failed);
    }

    @IsTest
    static void saveAuthorizationConfig_invalidEncryptionKey_throwsException() {
        GetNetPaymentUiFacade.AuthorizationConfigDto request = new GetNetPaymentUiFacade.AuthorizationConfigDto();
        request.configName = 'ConfiguracionPrueba';
        request.companyId = 'NEWCO';
        request.branchId = 'BR001';
        request.user = 'USR001';
        request.password = 'PASS001';
        request.encryptionKey = 'INVALID';
        request.data0 = 'DATA0';

        Boolean failed = false;
        Test.startTest();
        try {
            GetNetPaymentUiFacade.saveAuthorizationConfig(request);
        } catch (AuraHandledException e) {
            failed = true;
            System.assert(!String.isBlank(e.getMessage()));
        }
        Test.stopTest();

        System.assertEquals(true, failed);
    }

    @IsTest
    static void getObjectMappingObjectOptions_containsOpportunity() {
        Test.startTest();
        List<GetNetPaymentUiFacade.WorkspaceOptionDto> options = GetNetPaymentUiFacade.getObjectMappingObjectOptions();
        Test.stopTest();

        System.assert(options != null, 'La lista de objetos no debe ser null.');
        System.assert(options.size() > 0, 'Debe regresar al menos un objeto mapeable.');

        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        Boolean opportunityAccessible = false;
        if (globalDescribe.containsKey('opportunity')) {
            Schema.DescribeSObjectResult describeResult = globalDescribe.get('opportunity').getDescribe();
            opportunityAccessible = describeResult.isAccessible() &&
                describeResult.isQueryable() &&
                !describeResult.isCustomSetting() &&
                !describeResult.isDeprecatedAndHidden();
        }

        Set<String> optionValuesLower = new Set<String>();
        for (GetNetPaymentUiFacade.WorkspaceOptionDto option : options) {
            if (!String.isBlank(option.value)) {
                optionValuesLower.add(option.value.toLowerCase());
            }
        }

        if (opportunityAccessible) {
            System.assertEquals(
                true,
                optionValuesLower.contains('opportunity'),
                'Debe incluir Opportunity cuando es accesible/queryable.'
            );
        } else {
            System.assertEquals(
                true,
                optionValuesLower.size() > 0,
                'Si Opportunity no esta accesible, la lista aun debe contener objetos mapeables.'
            );
        }
    }

    @IsTest
    static void getObjectMappingObjectOptions_limitsStandardObjectsAndKeepsCustomObjects() {
        Test.startTest();
        List<GetNetPaymentUiFacade.WorkspaceOptionDto> options = GetNetPaymentUiFacade.getObjectMappingObjectOptions();
        Test.stopTest();

        Set<String> allowedStandardObjects = new Set<String>{ 'Opportunity', 'Order', 'Case', 'Account' };
        Boolean foundCustomObject = false;

        for (GetNetPaymentUiFacade.WorkspaceOptionDto option : options) {
            String objectApiName = option.value;
            if (objectApiName != null && objectApiName.endsWith('__c')) {
                foundCustomObject = true;
                continue;
            }

            System.assert(
                allowedStandardObjects.contains(objectApiName),
                'Solo deben incluirse objetos estandar permitidos o custom objects (__c). Objeto inesperado: ' +
                    objectApiName
            );
        }

        System.assertEquals(true, foundCustomObject, 'Debe incluir al menos un custom object mapeable (__c).');
    }

    @IsTest
    static void getObjectMappingFieldOptions_opportunity_containsValidFields() {
        Test.startTest();
        GetNetPaymentUiFacade.ObjectMappingFieldOptionsDto response =
            GetNetPaymentUiFacade.getObjectMappingFieldOptions('Opportunity');
        Test.stopTest();

        System.assert(response != null, 'La respuesta no debe ser null.');
        System.assert(response.referenceFieldOptions.size() > 0, 'Debe incluir opciones de referencia.');
        System.assert(response.amountFieldOptions.size() > 0, 'Debe incluir opciones de monto.');

        Boolean hasNameReference = false;
        for (GetNetPaymentUiFacade.WorkspaceOptionDto opt : response.referenceFieldOptions) {
            if (opt.value == 'Name') {
                hasNameReference = true;
                break;
            }
        }
        System.assertEquals(true, hasNameReference, 'Debe incluir Name como referencia valida.');

        Boolean hasAmountField = false;
        for (GetNetPaymentUiFacade.WorkspaceOptionDto opt : response.amountFieldOptions) {
            if (opt.value == 'Amount') {
                hasAmountField = true;
                break;
            }
        }
        System.assertEquals(true, hasAmountField, 'Debe incluir Amount como monto valido.');
    }

    @IsTest
    static void getObjectMappings_returnsList() {
        Test.startTest();
        List<GetNetPaymentUiFacade.ObjectMappingRowDto> rows = GetNetPaymentUiFacade.getObjectMappings();
        Test.stopTest();

        System.assert(rows != null, 'Debe regresar una lista (aunque este vacia).');
    }

    @IsTest
    static void saveObjectMappingDirect_validRequest_returnsSuccessInTestMode() {
        Test.startTest();
        GetNetPaymentUiFacade.SaveObjectMappingResultDto result =
            GetNetPaymentUiFacade.saveObjectMappingDirect(
                'Opportunity',
                'Name',
                'Amount',
                'MXN',
                'ConfiguracionPrueba'
            );
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assertEquals('Simulated', result.deploymentStatus);
        System.assert(!String.isBlank(result.developerName));
    }

    @IsTest
    static void saveObjectMappingDirect_sameObjectDifferentWorkspace_generatesDifferentDeveloperNames() {
        Test.startTest();
        GetNetPaymentUiFacade.SaveObjectMappingResultDto resultA =
            GetNetPaymentUiFacade.saveObjectMappingDirect(
                'Opportunity',
                'Name',
                'Amount',
                'MXN',
                'WS_A'
            );
        GetNetPaymentUiFacade.SaveObjectMappingResultDto resultB =
            GetNetPaymentUiFacade.saveObjectMappingDirect(
                'Opportunity',
                'Name',
                'Amount',
                'MXN',
                'WS_B'
            );
        Test.stopTest();

        System.assertNotEquals(resultA.developerName, resultB.developerName);
    }

    @IsTest
    static void saveObjectMappingDirect_missingObject_throwsException() {
        Boolean failed = false;

        Test.startTest();
        try {
            GetNetPaymentUiFacade.saveObjectMappingDirect('', 'Name', 'Amount', 'MXN', 'ConfiguracionPrueba');
        } catch (AuraHandledException e) {
            failed = true;
            System.assert(!String.isBlank(e.getMessage()));
        }
        Test.stopTest();

        System.assertEquals(true, failed);
    }

    @IsTest
    static void deactivateObjectMapping_validRequest_returnsSuccessInTestMode() {
        Test.startTest();
        GetNetPaymentUiFacade.SaveObjectMappingResultDto result =
            GetNetPaymentUiFacade.deactivateObjectMapping('MAP_Opportunity_ConfiguracionPrueba');
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assertEquals('Simulated', result.deploymentStatus);
        System.assertEquals('MAP_Opportunity_ConfiguracionPrueba', result.developerName);
    }

    @IsTest
    static void activateObjectMapping_validRequest_returnsSuccessInTestMode() {
        Test.startTest();
        GetNetPaymentUiFacade.SaveObjectMappingResultDto result =
            GetNetPaymentUiFacade.activateObjectMapping('MAP_Opportunity_ConfiguracionPrueba');
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assertEquals('Simulated', result.deploymentStatus);
        System.assertEquals('MAP_Opportunity_ConfiguracionPrueba', result.developerName);
    }

    @IsTest
    static void deactivateObjectMapping_blankDeveloperName_throwsException() {
        Boolean failed = false;

        Test.startTest();
        try {
            GetNetPaymentUiFacade.deactivateObjectMapping('');
        } catch (AuraHandledException e) {
            failed = true;
            System.assert(!String.isBlank(e.getMessage()));
        }
        Test.stopTest();

        System.assertEquals(true, failed);
    }

    @IsTest
    static void deleteObjectMapping_validRequest_returnsSuccessInTestMode() {
        Test.startTest();
        GetNetPaymentUiFacade.SaveObjectMappingResultDto result =
            GetNetPaymentUiFacade.deleteObjectMapping('MAP_Opportunity_ConfiguracionPrueba');
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assertEquals('Simulated', result.deploymentStatus);
        System.assertEquals('MAP_Opportunity_ConfiguracionPrueba', result.developerName);
    }

    @IsTest
    static void deleteObjectMapping_blankDeveloperName_throwsException() {
        Boolean failed = false;

        Test.startTest();
        try {
            GetNetPaymentUiFacade.deleteObjectMapping('');
        } catch (AuraHandledException e) {
            failed = true;
            System.assert(!String.isBlank(e.getMessage()));
        }
        Test.stopTest();

        System.assertEquals(true, failed);
    }

    @IsTest
    static void activateObjectMapping_blankDeveloperName_throwsException() {
        Boolean failed = false;

        Test.startTest();
        try {
            GetNetPaymentUiFacade.activateObjectMapping('');
        } catch (AuraHandledException e) {
            failed = true;
            System.assert(!String.isBlank(e.getMessage()));
        }
        Test.stopTest();

        System.assertEquals(true, failed);
    }

    @IsTest
    static void getMetadataFieldConfigs_returnsRows() {
        Test.startTest();
        List<GetNetPaymentUiFacade.MetadataFieldConfigDto> rows = GetNetPaymentUiFacade.getMetadataFieldConfigs(null);
        Test.stopTest();

        System.assert(rows.size() > 0, 'Debe regresar al menos una configuracion.');
        System.assert(!String.isBlank(rows[0].developerName));
        System.assert(!String.isBlank(rows[0].fieldApiName));
    }

    @IsTest
    static void getMetadataWorkspaceOptions_returnsUniqueSortedRows() {
        Test.startTest();
        List<GetNetPaymentUiFacade.WorkspaceOptionDto> options = GetNetPaymentUiFacade.getMetadataWorkspaceOptions();
        Test.stopTest();

        System.assert(options.size() > 0, 'Debe regresar al menos un workspace.');

        Set<String> seenValues = new Set<String>();
        String previousValue = null;
        Boolean foundDefault = false;
        for (GetNetPaymentUiFacade.WorkspaceOptionDto option : options) {
            System.assert(!String.isBlank(option.value), 'Workspace value no debe ser vacio.');
            System.assert(!seenValues.contains(option.value), 'No debe haber workspaces duplicados.');
            seenValues.add(option.value);

            if (option.value == 'ConfiguracionPrueba') {
                foundDefault = true;
            }

            if (previousValue != null) {
                System.assert(previousValue.compareTo(option.value) <= 0, 'Los workspaces deben venir ordenados.');
            }
            previousValue = option.value;
        }

        System.assertEquals(true, foundDefault, 'Metadata Workspace Options debe incluir ConfiguracionPrueba.');
    }

    @IsTest
    static void saveMetadataFieldConfig_validRequest_returnsSuccessInTestMode() {
        GetNetPaymentUiFacade.MetadataFieldConfigDto request = new GetNetPaymentUiFacade.MetadataFieldConfigDto();
        request.workspace = 'ConfiguracionPrueba';
        request.fieldLabel = 'Canal QA';
        request.fieldApiName = 'canal_qa';
        request.dataType = 'Text';
        request.required = true;
        request.xmlTag = 'canal_qa';
        request.sortOrder = 50;
        request.active = true;

        Test.startTest();
        GetNetPaymentUiFacade.SaveMetadataFieldConfigResultDto result = GetNetPaymentUiFacade.saveMetadataFieldConfig(
            request
        );
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assertEquals('Simulated', result.deploymentStatus);
        System.assert(!String.isBlank(result.developerName));
    }

    @IsTest
    static void saveMetadataFieldConfigDirect_validRequest_returnsSuccessInTestMode() {
        Test.startTest();
        GetNetPaymentUiFacade.SaveMetadataFieldConfigResultDto result =
            GetNetPaymentUiFacade.saveMetadataFieldConfigDirect(
                null,
                'ConfiguracionPrueba',
                'Canal QA',
                'canal_qa',
                'Text',
                true,
                'canal_qa',
                50,
                true
            );
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assertEquals('Simulated', result.deploymentStatus);
        System.assert(!String.isBlank(result.developerName));
    }

    @IsTest
    static void saveMetadataFieldConfig_invalidFieldApi_throwsException() {
        GetNetPaymentUiFacade.MetadataFieldConfigDto request = new GetNetPaymentUiFacade.MetadataFieldConfigDto();
        request.workspace = 'ConfiguracionPrueba';
        request.fieldLabel = 'Canal QA';
        request.fieldApiName = '1campo-invalido';
        request.dataType = 'Text';
        request.required = false;
        request.active = true;

        Boolean failed = false;

        Test.startTest();
        try {
            GetNetPaymentUiFacade.saveMetadataFieldConfig(request);
        } catch (AuraHandledException e) {
            failed = true;
            System.assert(!String.isBlank(e.getMessage()));
        }
        Test.stopTest();

        System.assertEquals(true, failed);
    }

    @IsTest
    static void deactivateMetadataFieldConfig_validRequest_returnsSuccessInTestMode() {
        List<GetNetPaymentUiFacade.MetadataFieldConfigDto> rows = GetNetPaymentUiFacade.getMetadataFieldConfigs(null);
        System.assert(rows.size() > 0, 'Debe existir al menos una configuracion para desactivar.');

        Test.startTest();
        GetNetPaymentUiFacade.SaveMetadataFieldConfigResultDto result =
            GetNetPaymentUiFacade.deactivateMetadataFieldConfig(rows[0].developerName);
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assertEquals('Simulated', result.deploymentStatus);
        System.assertEquals(rows[0].developerName, result.developerName);
    }

    @IsTest
    static void deactivateMetadataFieldConfig_blankDeveloperName_throwsException() {
        Boolean failed = false;

        Test.startTest();
        try {
            GetNetPaymentUiFacade.deactivateMetadataFieldConfig('');
        } catch (AuraHandledException e) {
            failed = true;
            System.assert(!String.isBlank(e.getMessage()));
        }
        Test.stopTest();

        System.assertEquals(true, failed);
    }

    @IsTest
    static void getWorkspaceOptions_containsConfiguracionPrueba() {
        Test.startTest();
        List<GetNetPaymentUiFacade.WorkspaceOptionDto> options = GetNetPaymentUiFacade.getWorkspaceOptions();
        Test.stopTest();

        System.assert(options.size() > 0, 'Debe regresar workspaces.');

        Boolean found = false;
        for (GetNetPaymentUiFacade.WorkspaceOptionDto option : options) {
            if (option.value == 'ConfiguracionPrueba') {
                found = true;
                break;
            }
        }

        System.assertEquals(true, found, 'Debe incluir ConfiguracionPrueba.');
    }

    @IsTest
    static void getQuickPaymentFieldDefinitions_returnsWorkspaceFields() {
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
            )
        };

        Test.startTest();
        List<PaymentLinkMetadataService.MetadataFieldDefinitionDto> defs =
            GetNetPaymentUiFacade.getQuickPaymentFieldDefinitions('ConfiguracionPrueba');
        Test.stopTest();

        System.assert(defs.size() > 0, 'Debe regresar definiciones de metadata.');
        System.assert(!String.isBlank(defs[0].apiName));

        PaymentLinkMetadataService.definitionOverrides = null;
    }

    @IsTest
    static void generateQuickPayment_success_createsAndGeneratesLink() {
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

        GetNetPaymentUiFacade.QuickPaymentRequestDto request = new GetNetPaymentUiFacade.QuickPaymentRequestDto();
        request.reference = 'QP-REF-001';
        request.amount = 349.99;
        request.currencyCode = 'USD';
        request.concept = 'Quick Payment Test';
        request.customerName = 'cliente@correo.com';
        request.workspace = 'ConfiguracionPrueba';
        request.metadataJson = '{"canal":"W","producto":"Mouse"}';

        Test.startTest();
        GetNetPaymentUiFacade.QuickPaymentResultDto result = GetNetPaymentUiFacade.generateQuickPayment(request);
        Test.stopTest();

        System.assertNotEquals(null, result.paymentLinkId);
        System.assert(!String.isBlank(result.paymentUrl));
        System.assertEquals('Pending', result.status);
        System.assertEquals('USD', result.currencyCode);

        Payment_Link__c stored = [
            SELECT Currency__c, Status__c, Payment_URL__c, Metadata_JSON__c, Metadata_Index__c
            FROM Payment_Link__c
            WHERE Id = :result.paymentLinkId
            LIMIT 1
        ];

        System.assertEquals('USD', stored.Currency__c);
        System.assertEquals('Pending', stored.Status__c);
        System.assert(!String.isBlank(stored.Payment_URL__c));
        System.assert(stored.Metadata_JSON__c.contains('"canal":"W"'));
        System.assert(stored.Metadata_Index__c.contains('canal=W'));

        List<Payment_Link_Metadata__c> metadataRows = [
            SELECT Id
            FROM Payment_Link_Metadata__c
            WHERE Payment_Link__c = :result.paymentLinkId
        ];
        System.assert(metadataRows.size() > 0, 'Debe persistir metadata tipada.');
        PaymentLinkMetadataService.definitionOverrides = null;
    }

    @IsTest
    static void generateQuickPayment_duplicateReference_returnsExistingLink() {
        Payment_Link__c existing = new Payment_Link__c(
            Reference__c = 'QP-REF-DUP-001',
            Amount__c = 120,
            Concept__c = 'Existing',
            Customer_Name__c = 'existing@correo.com',
            Workspace__c = 'ConfiguracionPrueba',
            Currency__c = 'MXN',
            Status__c = 'Pending',
            Payment_URL__c = 'https://example.test/pay/existing'
        );
        insert existing;

        GetNetPaymentUiFacade.QuickPaymentRequestDto request = new GetNetPaymentUiFacade.QuickPaymentRequestDto();
        request.reference = 'QP-REF-DUP-001';
        request.amount = 349.99;
        request.currencyCode = 'USD';
        request.concept = 'Quick Payment Test';
        request.customerName = 'cliente@correo.com';
        request.workspace = 'ConfiguracionPrueba';
        request.metadataJson = '{"canal":"W","producto":"Mouse"}';

        Test.startTest();
        GetNetPaymentUiFacade.QuickPaymentResultDto result = GetNetPaymentUiFacade.generateQuickPayment(request);
        Test.stopTest();

        System.assertEquals(existing.Id, result.paymentLinkId, 'Debe reutilizar la liga existente por referencia.');
        System.assertEquals(true, result.wasExisting, 'Debe marcar cuando la liga ya existia.');
        System.assert(result.message.contains('Ya existe una liga para la referencia'));

        Integer totalByReference = [
            SELECT COUNT()
            FROM Payment_Link__c
            WHERE Reference__c = 'QP-REF-DUP-001'
        ];
        System.assertEquals(1, totalByReference, 'No debe crear un duplicado para la misma referencia.');
    }
}
