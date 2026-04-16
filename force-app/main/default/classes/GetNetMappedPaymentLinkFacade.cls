public with sharing class GetNetMappedPaymentLinkFacade {
    private static final String DEFAULT_WORKSPACE = 'ConfiguracionPrueba';
    private static final String DEFAULT_CURRENCY = 'MXN';
    private static final Set<String> ALLOWED_CURRENCIES = new Set<String>{ 'MXN', 'USD' };

    private class ObjectMappingConfig {
        public String developerName;
        public String objectApiName;
        public String referenceField;
        public String amountField;
        public String currencyCode;
        public String workspace;
    }

    @TestVisible
    private static Map<String, ObjectMappingConfig> testMappingOverridesByObject;

    public class MappedRecordContextDto {
        @AuraEnabled
        public Id recordId;

        @AuraEnabled
        public String objectApiName;

        @AuraEnabled
        public String mappingDeveloperName;

        @AuraEnabled
        public String referenceField;

        @AuraEnabled
        public String amountField;

        @AuraEnabled
        public String reference;

        @AuraEnabled
        public Decimal amount;

        @AuraEnabled
        public String currencyCode;

        @AuraEnabled
        public String concept;

        @AuraEnabled
        public String customerName;

        @AuraEnabled
        public String workspace;

        @AuraEnabled
        public Boolean hasExistingLink;

        @AuraEnabled
        public Id existingPaymentLinkId;

        @AuraEnabled
        public String existingPaymentUrl;

        @AuraEnabled
        public String existingStatus;

        @AuraEnabled
        public String existingMetadataJson;

        @AuraEnabled
        public String existingMetadataIndex;

        @AuraEnabled
        public String message;
    }

    public class GenerateMappedPaymentLinkRequestDto {
        @AuraEnabled
        public Id recordId;

        @AuraEnabled
        public String objectApiName;

        @AuraEnabled
        public String reference;

        @AuraEnabled
        public Decimal amount;

        @AuraEnabled
        public String currencyCode;

        @AuraEnabled
        public String concept;

        @AuraEnabled
        public String customerName;

        @AuraEnabled
        public String workspace;

        @AuraEnabled
        public String metadataJson;
    }

    public class GenerateMappedPaymentLinkResultDto {
        @AuraEnabled
        public Id paymentLinkId;

        @AuraEnabled
        public String paymentUrl;

        @AuraEnabled
        public String status;

        @AuraEnabled
        public String workspace;

        @AuraEnabled
        public String currencyCode;

        @AuraEnabled
        public String metadataJson;

        @AuraEnabled
        public String metadataIndex;

        @AuraEnabled
        public Boolean wasExisting;

        @AuraEnabled
        public String message;
    }

    @AuraEnabled
    public static MappedRecordContextDto getMappedRecordContext(Id recordId, String objectApiName, String workspace) {
        if (recordId == null) {
            throw new AuraHandledException('Record Id es obligatorio.');
        }

        String resolvedObjectApiName = resolveRecordObjectApiName(recordId, objectApiName);
        String requestedWorkspace = trimToNull(workspace);
        ObjectMappingConfig mapping = requireActiveMapping(resolvedObjectApiName, requestedWorkspace);

        validateMappingAgainstObject(mapping, resolvedObjectApiName);
        SObject sourceRecord = fetchSourceRecord(recordId, resolvedObjectApiName, mapping);

        String referenceValue = readReferenceValue(sourceRecord, mapping.referenceField);
        Decimal amountValue = readAmountValue(sourceRecord, mapping.amountField);
        String currencyValue = normalizeCurrencyCode(mapping.currencyCode, false);
        String workspaceValue = resolveWorkspace(mapping.workspace);

        MappedRecordContextDto response = buildMappedRecordContextDto(
            recordId,
            resolvedObjectApiName,
            mapping,
            referenceValue,
            amountValue,
            currencyValue,
            workspaceValue
        );

        Payment_Link__c existing = findPaymentLinkByReference(referenceValue, false);
        applyExistingPaymentLinkToContext(response, existing);

        return response;
    }

    @AuraEnabled
    public static GenerateMappedPaymentLinkResultDto generateFromMappedRecord(
        GenerateMappedPaymentLinkRequestDto request
    ) {
        if (request == null) {
            throw new AuraHandledException('La solicitud de generacion es obligatoria.');
        }
        if (request.recordId == null) {
            throw new AuraHandledException('Record Id es obligatorio.');
        }

        String resolvedObjectApiName = resolveRecordObjectApiName(request.recordId, request.objectApiName);
        String requestedWorkspace = trimToNull(request.workspace);
        ObjectMappingConfig mapping = requireActiveMapping(resolvedObjectApiName, requestedWorkspace);
        validateMappingAgainstObject(mapping, resolvedObjectApiName);
        validateGenerateRequest(request);

        String resolvedWorkspace = resolveWorkspace(request.workspace, mapping.workspace);
        String resolvedCurrency = resolveCurrencyForGeneration(request.currencyCode, mapping.currencyCode);

        String reference = request.reference.trim();
        Payment_Link__c existing = findPaymentLinkByReference(reference, false);
        Boolean wasExisting = existing != null;

        Payment_Link__c paymentLink = buildDraftPaymentLink(
            wasExisting ? existing : new Payment_Link__c(),
            request,
            reference,
            resolvedWorkspace,
            resolvedCurrency
        );

        Payment_Link__c generated = PaymentLinkService.generateLinkFromDraft(paymentLink);
        return buildGenerateResponseDto(generated, wasExisting);
    }

    @AuraEnabled
    public static GenerateMappedPaymentLinkResultDto generateFromMappedRecordDirect(
        Id recordId,
        String objectApiName,
        String reference,
        Decimal amount,
        String currencyCode,
        String concept,
        String customerName,
        String workspace,
        String metadataJson
    ) {
        return generateFromMappedRecord(
            toGenerateMappedPaymentLinkRequest(
                recordId,
                objectApiName,
                reference,
                amount,
                currencyCode,
                concept,
                customerName,
                workspace,
                metadataJson
            )
        );
    }

    private static GenerateMappedPaymentLinkRequestDto toGenerateMappedPaymentLinkRequest(
        Id recordId,
        String objectApiName,
        String reference,
        Decimal amount,
        String currencyCode,
        String concept,
        String customerName,
        String workspace,
        String metadataJson
    ) {
        GenerateMappedPaymentLinkRequestDto request = new GenerateMappedPaymentLinkRequestDto();
        request.recordId = recordId;
        request.objectApiName = objectApiName;
        request.reference = reference;
        request.amount = amount;
        request.currencyCode = currencyCode;
        request.concept = concept;
        request.customerName = customerName;
        request.workspace = workspace;
        request.metadataJson = metadataJson;
        return request;
    }

    private static ObjectMappingConfig requireActiveMapping(String objectApiName, String requestedWorkspace) {
        ObjectMappingConfig mapping = loadActiveMapping(objectApiName, requestedWorkspace);
        if (mapping != null) {
            return mapping;
        }

        if (!String.isBlank(requestedWorkspace)) {
            throw new AuraHandledException(
                'No existe mapping activo para el objeto ' +
                objectApiName +
                ' en el workspace ' +
                requestedWorkspace +
                '.'
            );
        }

        throw new AuraHandledException(
            'No existe mapping activo para el objeto ' + objectApiName + '.'
        );
    }

    private static MappedRecordContextDto buildMappedRecordContextDto(
        Id recordId,
        String objectApiName,
        ObjectMappingConfig mapping,
        String reference,
        Decimal amount,
        String currencyCode,
        String workspace
    ) {
        MappedRecordContextDto response = new MappedRecordContextDto();
        response.recordId = recordId;
        response.objectApiName = objectApiName;
        response.mappingDeveloperName = mapping.developerName;
        response.referenceField = mapping.referenceField;
        response.amountField = mapping.amountField;
        response.reference = reference;
        response.amount = amount;
        response.currencyCode = currencyCode;
        response.workspace = workspace;
        response.concept = buildDefaultConcept(objectApiName, reference);
        response.customerName = '';
        response.hasExistingLink = false;
        response.message = 'Datos precargados desde el mapping activo.';
        return response;
    }

    private static void applyExistingPaymentLinkToContext(
        MappedRecordContextDto response,
        Payment_Link__c existingPaymentLink
    ) {
        if (existingPaymentLink == null) {
            return;
        }

        response.hasExistingLink = true;
        response.existingPaymentLinkId = existingPaymentLink.Id;
        response.existingPaymentUrl = existingPaymentLink.Payment_URL__c;
        response.existingStatus = existingPaymentLink.Status__c;
        response.existingMetadataJson = existingPaymentLink.Metadata_JSON__c;
        response.existingMetadataIndex = existingPaymentLink.Metadata_Index__c;
        response.currencyCode = String.isBlank(existingPaymentLink.Currency__c)
            ? response.currencyCode
            : existingPaymentLink.Currency__c;
        response.workspace = String.isBlank(existingPaymentLink.Workspace__c)
            ? response.workspace
            : existingPaymentLink.Workspace__c;
        response.amount = existingPaymentLink.Amount__c == null ? response.amount : existingPaymentLink.Amount__c;
        response.concept = String.isBlank(existingPaymentLink.Concept__c)
            ? response.concept
            : existingPaymentLink.Concept__c;
        response.customerName = String.isBlank(existingPaymentLink.Customer_Name__c)
            ? response.customerName
            : existingPaymentLink.Customer_Name__c;
        response.message = 'Ya existe una liga para esta referencia. Puedes reutilizarla o regenerarla.';
    }

    private static Payment_Link__c buildDraftPaymentLink(
        Payment_Link__c paymentLink,
        GenerateMappedPaymentLinkRequestDto request,
        String reference,
        String workspace,
        String currencyCode
    ) {
        paymentLink.Reference__c = reference;
        paymentLink.Amount__c = request.amount;
        paymentLink.Concept__c = request.concept.trim();
        paymentLink.Customer_Name__c = request.customerName.trim();
        paymentLink.Workspace__c = workspace;
        paymentLink.Currency__c = currencyCode;
        paymentLink.Metadata_JSON__c = request.metadataJson;
        paymentLink.Status__c = 'Draft';
        return paymentLink;
    }

    private static GenerateMappedPaymentLinkResultDto buildGenerateResponseDto(
        Payment_Link__c generated,
        Boolean wasExisting
    ) {
        GenerateMappedPaymentLinkResultDto response = new GenerateMappedPaymentLinkResultDto();
        response.paymentLinkId = generated.Id;
        response.paymentUrl = generated.Payment_URL__c;
        response.status = generated.Status__c;
        response.workspace = generated.Workspace__c;
        response.currencyCode = generated.Currency__c;
        response.metadataJson = generated.Metadata_JSON__c;
        response.metadataIndex = generated.Metadata_Index__c;
        response.wasExisting = wasExisting;
        response.message = wasExisting
            ? 'La referencia ya existia; la liga fue actualizada y generada nuevamente.'
            : 'Liga generada correctamente.';
        return response;
    }

    private static String resolveCurrencyForGeneration(String requestCurrencyCode, String mappingCurrencyCode) {
        String currencySource = String.isBlank(requestCurrencyCode) ? mappingCurrencyCode : requestCurrencyCode;
        return normalizeCurrencyCode(currencySource, true);
    }

    private static String buildDefaultConcept(String objectApiName, String reference) {
        return String.isBlank(reference) ? 'Pago ' + objectApiName : 'Pago ' + objectApiName + ' ' + reference;
    }

    private static String resolveWorkspace(String requestWorkspace, String mappingWorkspace) {
        if (!String.isBlank(requestWorkspace)) {
            return requestWorkspace.trim();
        }
        return resolveWorkspace(mappingWorkspace);
    }

    private static String resolveWorkspace(String rawWorkspace) {
        return String.isBlank(rawWorkspace) ? DEFAULT_WORKSPACE : rawWorkspace.trim();
    }

    private static String trimToNull(String value) {
        return String.isBlank(value) ? null : value.trim();
    }

    private static String resolveRecordObjectApiName(Id recordId, String objectApiName) {
        String resolvedFromId = recordId.getSObjectType().getDescribe().getName();
        String requested = String.isBlank(objectApiName) ? null : objectApiName.trim();

        if (!String.isBlank(requested) && requested != resolvedFromId) {
            throw new AuraHandledException(
                'ObjectApiName no coincide con el recordId. Esperado: ' + resolvedFromId + '.'
            );
        }

        return resolvedFromId;
    }

    private static ObjectMappingConfig loadActiveMapping(String objectApiName, String workspace) {
        String normalizedObject = normalizeKey(objectApiName);
        String normalizedWorkspace = normalizeKey(workspace);

        if (Test.isRunningTest() && testMappingOverridesByObject != null) {
            return loadTestActiveMapping(normalizedObject, normalizedWorkspace);
        }

        List<Payment_Link_Object_Mapping__mdt> rows = queryActiveMappings(objectApiName);

        if (rows.isEmpty()) {
            return null;
        }

        if (!String.isBlank(normalizedWorkspace)) {
            List<Payment_Link_Object_Mapping__mdt> matchingWorkspaceRows = filterMappingsByWorkspace(
                rows,
                normalizedWorkspace
            );

            if (matchingWorkspaceRows.size() > 1) {
                throw new AuraHandledException(
                    'Existe mas de un mapping activo para el objeto ' +
                    objectApiName +
                    ' en el workspace ' +
                    workspace +
                    '.'
                );
            }

            if (matchingWorkspaceRows.size() == 1) {
                return toObjectMappingConfig(matchingWorkspaceRows[0]);
            }

            return null;
        }

        List<Payment_Link_Object_Mapping__mdt> defaultWorkspaceRows = filterMappingsByWorkspace(
            rows,
            normalizeKey(DEFAULT_WORKSPACE)
        );

        if (defaultWorkspaceRows.size() > 1) {
            throw new AuraHandledException(
                'Existe mas de un mapping activo para el objeto ' +
                objectApiName +
                ' en el workspace por defecto ' +
                DEFAULT_WORKSPACE +
                '.'
            );
        }

        if (defaultWorkspaceRows.size() == 1) {
            return toObjectMappingConfig(defaultWorkspaceRows[0]);
        }

        Payment_Link_Object_Mapping__mdt row = rows[0];
        return toObjectMappingConfig(row);
    }

    private static ObjectMappingConfig loadTestActiveMapping(String normalizedObject, String normalizedWorkspace) {
        if (!String.isBlank(normalizedWorkspace)) {
            return testMappingOverridesByObject.get(buildMappingOverrideKey(normalizedObject, normalizedWorkspace));
        }

        ObjectMappingConfig defaultOverride = testMappingOverridesByObject.get(
            buildMappingOverrideKey(normalizedObject, normalizeKey(DEFAULT_WORKSPACE))
        );
        if (defaultOverride != null) {
            return defaultOverride;
        }

        String objectPrefix = normalizedObject + '|';
        for (String key : testMappingOverridesByObject.keySet()) {
            if (key.startsWith(objectPrefix)) {
                return testMappingOverridesByObject.get(key);
            }
        }

        return null;
    }

    private static List<Payment_Link_Object_Mapping__mdt> queryActiveMappings(String objectApiName) {
        return [
            SELECT
                DeveloperName,
                Object_API_Name__c,
                Reference_Field__c,
                Amount_Field__c,
                Currency__c,
                Workspace__c
            FROM Payment_Link_Object_Mapping__mdt
            WHERE Active__c = true AND Object_API_Name__c = :objectApiName
            ORDER BY Workspace__c ASC, DeveloperName ASC
        ];
    }

    private static List<Payment_Link_Object_Mapping__mdt> filterMappingsByWorkspace(
        List<Payment_Link_Object_Mapping__mdt> rows,
        String normalizedWorkspace
    ) {
        List<Payment_Link_Object_Mapping__mdt> filteredRows = new List<Payment_Link_Object_Mapping__mdt>();
        for (Payment_Link_Object_Mapping__mdt row : rows) {
            if (normalizeKey(row.Workspace__c) == normalizedWorkspace) {
                filteredRows.add(row);
            }
        }
        return filteredRows;
    }

    private static ObjectMappingConfig toObjectMappingConfig(Payment_Link_Object_Mapping__mdt row) {
        ObjectMappingConfig mapping = new ObjectMappingConfig();
        mapping.developerName = row.DeveloperName;
        mapping.objectApiName = row.Object_API_Name__c;
        mapping.referenceField = row.Reference_Field__c;
        mapping.amountField = row.Amount_Field__c;
        mapping.currencyCode = row.Currency__c;
        mapping.workspace = row.Workspace__c;
        return mapping;
    }

    private static void validateMappingAgainstObject(ObjectMappingConfig mapping, String objectApiName) {
        validateRequiredText('Reference Field', mapping.referenceField);
        validateRequiredText('Amount Field', mapping.amountField);

        Schema.DescribeSObjectResult objectDescribe = getObjectDescribeOrThrow(objectApiName);
        if (!objectDescribe.isAccessible() || !objectDescribe.isQueryable()) {
            throw new AuraHandledException(
                'No tienes acceso al objeto ' + objectApiName + ' para generar la liga.'
            );
        }

        Map<String, Schema.SObjectField> fieldMap = objectDescribe.fields.getMap();
        if (!fieldMap.containsKey(mapping.referenceField)) {
            throw new AuraHandledException(
                'Reference Field invalido para objeto ' + objectApiName + ': ' + mapping.referenceField + '.'
            );
        }
        if (!fieldMap.containsKey(mapping.amountField)) {
            throw new AuraHandledException(
                'Amount Field invalido para objeto ' + objectApiName + ': ' + mapping.amountField + '.'
            );
        }

        Schema.DescribeFieldResult referenceDescribe = fieldMap.get(mapping.referenceField).getDescribe();
        Schema.DescribeFieldResult amountDescribe = fieldMap.get(mapping.amountField).getDescribe();

        if (!referenceDescribe.isAccessible()) {
            throw new AuraHandledException('No tienes acceso al campo de referencia del mapping.');
        }
        if (!amountDescribe.isAccessible()) {
            throw new AuraHandledException('No tienes acceso al campo de monto del mapping.');
        }

        if (!isReferenceMappingFieldType(referenceDescribe.getType())) {
            throw new AuraHandledException('El campo de referencia del mapping no es valido.');
        }
        if (!isAmountMappingFieldType(amountDescribe.getType())) {
            throw new AuraHandledException('El campo de monto del mapping debe ser numerico o currency.');
        }
    }

    private static SObject fetchSourceRecord(Id recordId, String objectApiName, ObjectMappingConfig mapping) {
        List<String> queryFields = new List<String>{ mapping.referenceField };
        if (mapping.amountField != mapping.referenceField) {
            queryFields.add(mapping.amountField);
        }

        String soql =
            'SELECT ' +
            String.join(queryFields, ', ') +
            ' FROM ' +
            objectApiName +
            ' WHERE Id = :recordId LIMIT 1';

        List<SObject> rows = Database.query(soql);
        if (rows.isEmpty()) {
            throw new AuraHandledException('No se encontro el registro origen para generar la liga.');
        }

        return rows[0];
    }

    private static String readReferenceValue(SObject recordRow, String fieldApiName) {
        if (recordRow == null || String.isBlank(fieldApiName)) {
            return '';
        }
        Object rawValue = recordRow.get(fieldApiName);
        return rawValue == null ? '' : String.valueOf(rawValue).trim();
    }

    private static Decimal readAmountValue(SObject recordRow, String fieldApiName) {
        if (recordRow == null || String.isBlank(fieldApiName)) {
            return null;
        }
        Object rawValue = recordRow.get(fieldApiName);
        if (rawValue == null) {
            return null;
        }

        if (rawValue instanceof Decimal) {
            return (Decimal) rawValue;
        }
        if (rawValue instanceof Integer) {
            return Decimal.valueOf(String.valueOf((Integer) rawValue));
        }
        if (rawValue instanceof Long) {
            return Decimal.valueOf(String.valueOf((Long) rawValue));
        }
        if (rawValue instanceof Double) {
            return Decimal.valueOf(String.valueOf((Double) rawValue));
        }

        try {
            return Decimal.valueOf(String.valueOf(rawValue).trim());
        } catch (Exception e) {
            throw new AuraHandledException('No se pudo convertir el campo de monto del registro origen.');
        }
    }

    private static Payment_Link__c findPaymentLinkByReference(String reference, Boolean forUpdate) {
        if (String.isBlank(reference)) {
            return null;
        }

        String soql =
            'SELECT Id, Amount__c, Currency__c, Reference__c, Concept__c, Customer_Name__c, Expiration_Date__c, ' +
            'Workspace__c, Metadata_JSON__c, Metadata_Index__c, Status__c, Attempt_Count__c, Payment_URL__c, ' +
            'Provider_Transaction_ID__c, Raw_Request__c, Raw_Response__c ' +
            'FROM Payment_Link__c WHERE Reference__c = :reference LIMIT 1';
        if (forUpdate == true) {
            soql += ' FOR UPDATE';
        }

        List<Payment_Link__c> rows = Database.query(soql);
        return rows.isEmpty() ? null : rows[0];
    }

    private static void validateGenerateRequest(GenerateMappedPaymentLinkRequestDto request) {
        validateRequiredText('Reference', request.reference);
        validateRequiredText('Concept', request.concept);
        validateRequiredText('Customer Name', request.customerName);
        validateRequiredText('Workspace', request.workspace);

        if (request.amount == null || request.amount <= 0) {
            throw new AuraHandledException('Amount debe ser mayor a cero.');
        }
    }

    private static String normalizeCurrencyCode(String rawCurrency, Boolean required) {
        String normalized = String.isBlank(rawCurrency) ? '' : rawCurrency.trim().toUpperCase();
        if (String.isBlank(normalized)) {
            if (required == true) {
                throw new AuraHandledException('Currency es obligatorio.');
            }
            return DEFAULT_CURRENCY;
        }

        if (!ALLOWED_CURRENCIES.contains(normalized)) {
            throw new AuraHandledException('Currency invalido. Usa MXN o USD.');
        }
        return normalized;
    }

    private static Boolean isReferenceMappingFieldType(Schema.DisplayType displayType) {
        return displayType == Schema.DisplayType.Id ||
            displayType == Schema.DisplayType.Reference ||
            displayType == Schema.DisplayType.String ||
            displayType == Schema.DisplayType.TextArea ||
            displayType == Schema.DisplayType.Email ||
            displayType == Schema.DisplayType.Phone ||
            displayType == Schema.DisplayType.Url ||
            displayType == Schema.DisplayType.Picklist ||
            displayType == Schema.DisplayType.MultiPicklist ||
            displayType == Schema.DisplayType.EncryptedString;
    }

    private static Boolean isAmountMappingFieldType(Schema.DisplayType displayType) {
        return displayType == Schema.DisplayType.Currency ||
            displayType == Schema.DisplayType.Double ||
            displayType == Schema.DisplayType.Integer ||
            displayType == Schema.DisplayType.Long ||
            displayType == Schema.DisplayType.Percent;
    }

    private static Schema.DescribeSObjectResult getObjectDescribeOrThrow(String objectApiName) {
        String normalizedObjectApiName = String.isBlank(objectApiName) ? '' : objectApiName.trim();
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        if (!globalDescribe.containsKey(normalizedObjectApiName)) {
            throw new AuraHandledException('Object invalido para mapping: ' + normalizedObjectApiName + '.');
        }
        return globalDescribe.get(normalizedObjectApiName).getDescribe();
    }

    private static void validateRequiredText(String label, String value) {
        if (String.isBlank(value)) {
            throw new AuraHandledException(label + ' es obligatorio.');
        }
    }

    private static String normalizeKey(String value) {
        return String.isBlank(value) ? '' : value.trim().toLowerCase();
    }

    private static String buildMappingOverrideKey(String normalizedObjectApiName, String normalizedWorkspace) {
        return normalizedObjectApiName + '|' + normalizedWorkspace;
    }

    @TestVisible
    private static void setTestMappingOverride(
        String objectApiName,
        String referenceField,
        String amountField,
        String currencyCode,
        String workspace
    ) {
        if (testMappingOverridesByObject == null) {
            testMappingOverridesByObject = new Map<String, ObjectMappingConfig>();
        }

        ObjectMappingConfig mapping = new ObjectMappingConfig();
        mapping.developerName = 'TEST_' + (String.isBlank(objectApiName) ? 'UNKNOWN' : objectApiName);
        mapping.objectApiName = objectApiName;
        mapping.referenceField = referenceField;
        mapping.amountField = amountField;
        mapping.currencyCode = currencyCode;
        mapping.workspace = workspace;

        String mappingKey = buildMappingOverrideKey(normalizeKey(objectApiName), normalizeKey(workspace));
        testMappingOverridesByObject.put(mappingKey, mapping);
    }

    @TestVisible
    private static void useEmptyTestMappingOverrides() {
        testMappingOverridesByObject = new Map<String, ObjectMappingConfig>();
    }

    @TestVisible
    private static void clearTestMappingOverrides() {
        testMappingOverridesByObject = null;
    }
}
