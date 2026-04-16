public with sharing class GetNetPaymentUiFacade {
    private static final String DEFAULT_CONFIG_NAME = 'ConfiguracionPrueba';
    private static final String DEFAULT_GENERATE_PATH = '/gen';
    private static final Integer DEFAULT_TIMEOUT_MS = 15000;
    private static final Integer DEFAULT_MAX_RETRIES = 2;
    private static final String DEFAULT_CURRENCY = 'MXN';
    private static final Integer MAX_METADATA_DEVELOPER_NAME_LENGTH = 40;
    private static final Integer MAX_METADATA_LABEL_LENGTH = 40;
    private static final String OBJECT_MAPPING_DELETED_LABEL_PREFIX = '[DELETED] ';
    private static final Set<String> OBJECT_MAPPING_ALLOWED_STANDARD_OBJECTS = new Set<String>{
        'Opportunity',
        'Order',
        'Case',
        'Account'
    };
    private static final String CUSTOM_OBJECT_SUFFIX = '__c';

    public class AuthorizationConfigDto {
        @AuraEnabled
        public String configName;

        @AuraEnabled
        public String companyId;

        @AuraEnabled
        public String branchId;

        @AuraEnabled
        public String user;

        @AuraEnabled
        public String password;

        @AuraEnabled
        public String encryptionKey;

        @AuraEnabled
        public String data0;
    }

    public class SaveAuthorizationResultDto {
        @AuraEnabled
        public Boolean success;

        @AuraEnabled
        public String message;

        @AuraEnabled
        public String configName;

        @AuraEnabled
        public String deploymentId;

        @AuraEnabled
        public String deploymentStatus;
    }

    public class MetadataFieldConfigDto {
        @AuraEnabled
        public String developerName;

        @AuraEnabled
        public String workspace;

        @AuraEnabled
        public String fieldLabel;

        @AuraEnabled
        public String fieldApiName;

        @AuraEnabled
        public String dataType;

        @AuraEnabled
        public Boolean required;

        @AuraEnabled
        public String xmlTag;

        @AuraEnabled
        public Integer sortOrder;

        @AuraEnabled
        public Boolean active;
    }

    public class SaveMetadataFieldConfigResultDto {
        @AuraEnabled
        public Boolean success;

        @AuraEnabled
        public String message;

        @AuraEnabled
        public String developerName;

        @AuraEnabled
        public String deploymentId;

        @AuraEnabled
        public String deploymentStatus;
    }

    public class ObjectMappingFieldOptionsDto {
        @AuraEnabled
        public List<WorkspaceOptionDto> referenceFieldOptions;

        @AuraEnabled
        public List<WorkspaceOptionDto> amountFieldOptions;
    }

    public class ObjectMappingRowDto {
        @AuraEnabled
        public String id;

        @AuraEnabled
        public String developerName;

        @AuraEnabled
        public String objectApiName;

        @AuraEnabled
        public String referenceField;

        @AuraEnabled
        public String amountField;

        @AuraEnabled
        public String currencyCode;

        @AuraEnabled
        public String workspace;

        @AuraEnabled
        public Boolean active;

        @AuraEnabled
        public String status;
    }

    public class SaveObjectMappingResultDto {
        @AuraEnabled
        public Boolean success;

        @AuraEnabled
        public String message;

        @AuraEnabled
        public String developerName;

        @AuraEnabled
        public String deploymentId;

        @AuraEnabled
        public String deploymentStatus;
    }

    public class WorkspaceOptionDto {
        @AuraEnabled
        public String label;

        @AuraEnabled
        public String value;
    }

    public class QuickPaymentRequestDto {
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

    public class QuickPaymentResultDto {
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

    private class NoopDeployCallback implements Metadata.DeployCallback {
        public void handleResult(Metadata.DeployResult result, Metadata.DeployCallbackContext context) {
        }
    }

    @AuraEnabled(cacheable=true)
    public static AuthorizationConfigDto getAuthorizationConfig(String configName) {
        String resolvedConfigName = resolveConfigName(configName);
        PagosOnline_Config__mdt configRecord = findConfigOrNull(resolvedConfigName);

        AuthorizationConfigDto dto = new AuthorizationConfigDto();
        dto.configName = resolvedConfigName;

        if (configRecord != null) {
            dto.companyId = configRecord.CompanyId__c;
            dto.branchId = configRecord.BranchId__c;
            dto.user = configRecord.User__c;
            dto.password = configRecord.Password__c;
            dto.encryptionKey = configRecord.AESKeyHex__c;
            dto.data0 = configRecord.Data0__c;
        }

        return dto;
    }

    @AuraEnabled
    public static SaveAuthorizationResultDto saveAuthorizationConfig(AuthorizationConfigDto request) {
        System.debug(
            LoggingLevel.INFO,
            'GetNetPaymentUiFacade.saveAuthorizationConfig payload=' + JSON.serialize(request)
        );

        if (request == null) {
            throw new AuraHandledException('La configuracion de autorizacion es obligatoria.');
        }

        String resolvedConfigName = resolveConfigName(request.configName);
        validateAuthorizationRequest(request);

        PagosOnline_Config__mdt existingConfig = findConfigOrNull(resolvedConfigName);

        Metadata.CustomMetadata metadataRecord = new Metadata.CustomMetadata();
        metadataRecord.fullName = 'PagosOnline_Config__mdt.' + resolvedConfigName;
        metadataRecord.label = existingConfig == null || String.isBlank(existingConfig.MasterLabel)
            ? resolvedConfigName
            : existingConfig.MasterLabel;

        addMetadataValue(metadataRecord, 'CompanyId__c', request.companyId.trim());
        addMetadataValue(metadataRecord, 'BranchId__c', request.branchId.trim());
        addMetadataValue(metadataRecord, 'User__c', request.user.trim());
        addMetadataValue(metadataRecord, 'Password__c', request.password.trim());
        addMetadataValue(metadataRecord, 'AESKeyHex__c', request.encryptionKey.trim().toUpperCase());
        addMetadataValue(metadataRecord, 'Data0__c', request.data0.trim());

        if (existingConfig != null) {
            addMetadataValue(metadataRecord, 'GeneratePath__c', existingConfig.GeneratePath__c);
            addMetadataValue(metadataRecord, 'TimeoutMs__c', existingConfig.TimeoutMs__c);
            addMetadataValue(metadataRecord, 'MaxRetries__c', existingConfig.MaxRetries__c);
        } else {
            addMetadataValue(metadataRecord, 'GeneratePath__c', DEFAULT_GENERATE_PATH);
            addMetadataValue(metadataRecord, 'TimeoutMs__c', DEFAULT_TIMEOUT_MS);
            addMetadataValue(metadataRecord, 'MaxRetries__c', DEFAULT_MAX_RETRIES);
        }

        if (Test.isRunningTest()) {
            SaveAuthorizationResultDto simulated = new SaveAuthorizationResultDto();
            simulated.success = true;
            simulated.message = 'Validacion completada en prueba. Despliegue de metadata omitido.';
            simulated.configName = resolvedConfigName;
            simulated.deploymentStatus = 'Simulated';
            return simulated;
        }

        Metadata.DeployContainer container = new Metadata.DeployContainer();
        container.addMetadata(metadataRecord);

        Id deploymentId;
        try {
            deploymentId = Metadata.Operations.enqueueDeployment(container, new NoopDeployCallback());
        } catch (Exception e) {
            throw new AuraHandledException(
                'No fue posible iniciar el guardado de configuracion: ' + e.getMessage()
            );
        }

        SaveAuthorizationResultDto response = new SaveAuthorizationResultDto();
        response.success = true;
        response.configName = resolvedConfigName;
        response.deploymentId = deploymentId;
        response.deploymentStatus = 'Queued';
        response.message = 'Guardado enviado correctamente. Deployment Id: ' + deploymentId;

        return response;
    }

    @AuraEnabled
    public static SaveAuthorizationResultDto saveAuthorizationConfigDirect(
        String configName,
        String companyId,
        String branchId,
        String user,
        String password,
        String encryptionKey,
        String data0
    ) {
        System.debug(
            LoggingLevel.INFO,
            'GetNetPaymentUiFacade.saveAuthorizationConfigDirect payload=' +
            JSON.serialize(
                new Map<String, Object>{
                    'configName' => configName,
                    'companyId' => companyId,
                    'branchId' => branchId,
                    'user' => user,
                    'password' => password,
                    'encryptionKey' => encryptionKey,
                    'data0' => data0
                }
            )
        );

        AuthorizationConfigDto request = new AuthorizationConfigDto();
        request.configName = configName;
        request.companyId = companyId;
        request.branchId = branchId;
        request.user = user;
        request.password = password;
        request.encryptionKey = encryptionKey;
        request.data0 = data0;
        return saveAuthorizationConfig(request);
    }

    @AuraEnabled
    public static List<WorkspaceOptionDto> getObjectMappingObjectOptions() {
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        List<String> objectApiNames = new List<String>();

        for (String objectApiName : globalDescribe.keySet()) {
            Schema.DescribeSObjectResult objectDescribe = globalDescribe.get(objectApiName).getDescribe();
            String resolvedObjectApiName = objectDescribe.getName();
            if (!isObjectEligibleForMapping(objectDescribe)) {
                continue;
            }
            if (!isObjectAllowedForMapping(resolvedObjectApiName)) {
                continue;
            }

            objectApiNames.add(resolvedObjectApiName);
        }

        objectApiNames.sort();

        List<WorkspaceOptionDto> options = new List<WorkspaceOptionDto>();
        for (String objectApiName : objectApiNames) {
            WorkspaceOptionDto option = new WorkspaceOptionDto();
            option.label = objectApiName;
            option.value = objectApiName;
            options.add(option);
        }

        return options;
    }

    @AuraEnabled(cacheable=true)
    public static ObjectMappingFieldOptionsDto getObjectMappingFieldOptions(String objectApiName) {
        ObjectMappingFieldOptionsDto response = new ObjectMappingFieldOptionsDto();
        response.referenceFieldOptions = new List<WorkspaceOptionDto>();
        response.amountFieldOptions = new List<WorkspaceOptionDto>();

        if (String.isBlank(objectApiName)) {
            return response;
        }

        Schema.DescribeSObjectResult objectDescribe = getObjectDescribeOrThrow(objectApiName);
        Map<String, Schema.SObjectField> fieldMap = objectDescribe.fields.getMap();
        List<String> fieldApiNames = new List<String>();
        fieldApiNames.addAll(fieldMap.keySet());
        fieldApiNames.sort();

        for (String fieldApiName : fieldApiNames) {
            Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldApiName).getDescribe();
            if (!fieldDescribe.isAccessible()) {
                continue;
            }

            if (isReferenceMappingFieldType(fieldDescribe.getType())) {
                response.referenceFieldOptions.add(buildMappingFieldOption(fieldApiName, fieldDescribe.getLabel()));
            }
            if (isAmountMappingFieldType(fieldDescribe.getType())) {
                response.amountFieldOptions.add(buildMappingFieldOption(fieldApiName, fieldDescribe.getLabel()));
            }
        }

        return response;
    }

    @AuraEnabled
    public static List<ObjectMappingRowDto> getObjectMappings() {
        List<ObjectMappingRowDto> output = new List<ObjectMappingRowDto>();
        for (Payment_Link_Object_Mapping__mdt row : [
            SELECT
                DeveloperName,
                MasterLabel,
                Object_API_Name__c,
                Reference_Field__c,
                Amount_Field__c,
                Currency__c,
                Workspace__c,
                Active__c
            FROM Payment_Link_Object_Mapping__mdt
            ORDER BY Object_API_Name__c ASC, Workspace__c ASC, Active__c DESC, DeveloperName ASC
        ]) {
            if (isDeletedObjectMappingLabel(row.MasterLabel)) {
                continue;
            }

            ObjectMappingRowDto dto = new ObjectMappingRowDto();
            dto.id = row.DeveloperName;
            dto.developerName = row.DeveloperName;
            dto.objectApiName = row.Object_API_Name__c;
            dto.referenceField = row.Reference_Field__c;
            dto.amountField = row.Amount_Field__c;
            dto.currencyCode = row.Currency__c;
            dto.workspace = row.Workspace__c;
            dto.active = row.Active__c;
            dto.status = row.Active__c ? 'Active' : 'Inactive';
            output.add(dto);
        }
        return output;
    }

    @AuraEnabled
    public static SaveObjectMappingResultDto saveObjectMappingDirect(
        String objectApiName,
        String referenceField,
        String amountField,
        String currencyCode,
        String workspace
    ) {
        return saveObjectMappingDirectV2(
            null,
            objectApiName,
            referenceField,
            amountField,
            currencyCode,
            workspace,
            false
        );
    }

    @AuraEnabled
    public static SaveObjectMappingResultDto saveObjectMappingDirectV2(
        String developerName,
        String objectApiName,
        String referenceField,
        String amountField,
        String currencyCode,
        String workspace,
        Boolean active
    ) {
        validateRequiredText('Object', objectApiName);
        validateRequiredText('Reference Field', referenceField);
        validateRequiredText('Amount Field', amountField);
        validateRequiredText('Currency', currencyCode);
        validateRequiredText('Workspace', workspace);

        String normalizedObjectApiName = objectApiName.trim();
        String normalizedReferenceField = referenceField.trim();
        String normalizedAmountField = amountField.trim();
        String normalizedCurrency = normalizeObjectMappingCurrency(currencyCode);
        String normalizedWorkspace = workspace.trim();

        validateObjectMappingFields(
            normalizedObjectApiName,
            normalizedReferenceField,
            normalizedAmountField
        );

        Boolean normalizedActive = active == true;
        String resolvedDeveloperName = resolveObjectMappingDeveloperName(
            developerName,
            normalizedObjectApiName,
            normalizedWorkspace
        );
        Payment_Link_Object_Mapping__mdt existing = findObjectMappingOrNull(resolvedDeveloperName);

        Metadata.CustomMetadata metadataRecord = new Metadata.CustomMetadata();
        metadataRecord.fullName = 'Payment_Link_Object_Mapping__mdt.' + resolvedDeveloperName;
        metadataRecord.label = existing == null || String.isBlank(existing.MasterLabel)
            ? truncateObjectMappingLabel(normalizedObjectApiName + ' ' + normalizedWorkspace + ' Mapping ' + resolvedDeveloperName)
            : existing.MasterLabel;

        addMetadataValue(metadataRecord, 'Object_API_Name__c', normalizedObjectApiName);
        addMetadataValue(metadataRecord, 'Reference_Field__c', normalizedReferenceField);
        addMetadataValue(metadataRecord, 'Amount_Field__c', normalizedAmountField);
        addMetadataValue(metadataRecord, 'Currency__c', normalizedCurrency);
        addMetadataValue(metadataRecord, 'Workspace__c', normalizedWorkspace);
        addMetadataValue(metadataRecord, 'Active__c', normalizedActive);

        if (Test.isRunningTest()) {
            SaveObjectMappingResultDto simulated = new SaveObjectMappingResultDto();
            simulated.success = true;
            simulated.developerName = resolvedDeveloperName;
            simulated.deploymentStatus = 'Simulated';
            simulated.message = 'Validacion completada en prueba. Despliegue de metadata omitido.';
            return simulated;
        }

        Metadata.DeployContainer container = new Metadata.DeployContainer();
        container.addMetadata(metadataRecord);
        if (normalizedActive) {
            List<Payment_Link_Object_Mapping__mdt> siblingMappings = findObjectMappingsByObjectWorkspace(
                normalizedObjectApiName,
                normalizedWorkspace
            );
            for (Payment_Link_Object_Mapping__mdt sibling : siblingMappings) {
                if (sibling.DeveloperName == resolvedDeveloperName || sibling.Active__c != true) {
                    continue;
                }
                container.addMetadata(
                    buildObjectMappingMetadataRecord(
                        sibling.DeveloperName,
                        String.isBlank(sibling.MasterLabel) ? sibling.DeveloperName : sibling.MasterLabel,
                        sibling.Object_API_Name__c,
                        sibling.Reference_Field__c,
                        sibling.Amount_Field__c,
                        sibling.Currency__c,
                        sibling.Workspace__c,
                        false
                    )
                );
            }
        }

        Id deploymentId;
        try {
            deploymentId = Metadata.Operations.enqueueDeployment(container, new NoopDeployCallback());
        } catch (Exception e) {
            throw new AuraHandledException(
                'No fue posible iniciar el guardado de object mapping: ' + e.getMessage()
            );
        }

        SaveObjectMappingResultDto response = new SaveObjectMappingResultDto();
        response.success = true;
        response.developerName = resolvedDeveloperName;
        response.deploymentId = deploymentId;
        response.deploymentStatus = 'Queued';
        response.message = 'Guardado enviado correctamente. Deployment Id: ' + deploymentId;
        return response;
    }

    @AuraEnabled
    public static SaveObjectMappingResultDto activateObjectMapping(String developerName) {
        if (String.isBlank(developerName)) {
            throw new AuraHandledException('Developer Name es obligatorio para activar mapping.');
        }

        String normalizedDeveloperName = normalizeMetadataToken(developerName);
        if (Test.isRunningTest()) {
            SaveObjectMappingResultDto simulated = new SaveObjectMappingResultDto();
            simulated.success = true;
            simulated.developerName = normalizedDeveloperName;
            simulated.deploymentStatus = 'Simulated';
            simulated.message = 'Validacion completada en prueba. Despliegue de metadata omitido.';
            return simulated;
        }

        Payment_Link_Object_Mapping__mdt selected = findObjectMappingOrNull(normalizedDeveloperName);
        if (selected == null) {
            throw new AuraHandledException(
                'No existe object mapping con Developer Name: ' + normalizedDeveloperName + '.'
            );
        }
        if (isDeletedObjectMappingLabel(selected.MasterLabel)) {
            throw new AuraHandledException('El mapping seleccionado esta borrado y no se puede activar.');
        }

        Metadata.DeployContainer container = new Metadata.DeployContainer();
        container.addMetadata(
            buildObjectMappingMetadataRecord(
                selected.DeveloperName,
                String.isBlank(selected.MasterLabel) ? selected.DeveloperName : selected.MasterLabel,
                selected.Object_API_Name__c,
                selected.Reference_Field__c,
                selected.Amount_Field__c,
                selected.Currency__c,
                selected.Workspace__c,
                true
            )
        );

        List<Payment_Link_Object_Mapping__mdt> siblingMappings = findObjectMappingsByObjectWorkspace(
            selected.Object_API_Name__c,
            selected.Workspace__c
        );
        for (Payment_Link_Object_Mapping__mdt sibling : siblingMappings) {
            if (sibling.DeveloperName == selected.DeveloperName || sibling.Active__c != true) {
                continue;
            }
            container.addMetadata(
                buildObjectMappingMetadataRecord(
                    sibling.DeveloperName,
                    String.isBlank(sibling.MasterLabel) ? sibling.DeveloperName : sibling.MasterLabel,
                    sibling.Object_API_Name__c,
                    sibling.Reference_Field__c,
                    sibling.Amount_Field__c,
                    sibling.Currency__c,
                    sibling.Workspace__c,
                    false
                )
            );
        }

        Id deploymentId;
        try {
            deploymentId = Metadata.Operations.enqueueDeployment(container, new NoopDeployCallback());
        } catch (Exception e) {
            throw new AuraHandledException(
                'No fue posible iniciar la activacion de object mapping: ' + e.getMessage()
            );
        }

        SaveObjectMappingResultDto response = new SaveObjectMappingResultDto();
        response.success = true;
        response.developerName = normalizedDeveloperName;
        response.deploymentId = deploymentId;
        response.deploymentStatus = 'Queued';
        response.message = 'Activacion enviada correctamente. Deployment Id: ' + deploymentId;
        return response;
    }

    @AuraEnabled
    public static SaveObjectMappingResultDto deactivateObjectMapping(String developerName) {
        if (String.isBlank(developerName)) {
            throw new AuraHandledException('Developer Name es obligatorio para eliminar mapping.');
        }

        String normalizedDeveloperName = normalizeMetadataToken(developerName);

        if (Test.isRunningTest()) {
            SaveObjectMappingResultDto simulated = new SaveObjectMappingResultDto();
            simulated.success = true;
            simulated.developerName = normalizedDeveloperName;
            simulated.deploymentStatus = 'Simulated';
            simulated.message = 'Validacion completada en prueba. Despliegue de metadata omitido.';
            return simulated;
        }

        Payment_Link_Object_Mapping__mdt existing = findObjectMappingOrNull(normalizedDeveloperName);
        if (existing == null) {
            throw new AuraHandledException(
                'No existe object mapping con Developer Name: ' + normalizedDeveloperName + '.'
            );
        }

        Metadata.CustomMetadata metadataRecord = new Metadata.CustomMetadata();
        metadataRecord.fullName = 'Payment_Link_Object_Mapping__mdt.' + normalizedDeveloperName;
        metadataRecord.label = String.isBlank(existing.MasterLabel) ? normalizedDeveloperName : existing.MasterLabel;

        addMetadataValue(metadataRecord, 'Object_API_Name__c', existing.Object_API_Name__c);
        addMetadataValue(metadataRecord, 'Reference_Field__c', existing.Reference_Field__c);
        addMetadataValue(metadataRecord, 'Amount_Field__c', existing.Amount_Field__c);
        addMetadataValue(metadataRecord, 'Currency__c', existing.Currency__c);
        addMetadataValue(metadataRecord, 'Workspace__c', existing.Workspace__c);
        addMetadataValue(metadataRecord, 'Active__c', false);

        Metadata.DeployContainer container = new Metadata.DeployContainer();
        container.addMetadata(metadataRecord);

        Id deploymentId;
        try {
            deploymentId = Metadata.Operations.enqueueDeployment(container, new NoopDeployCallback());
        } catch (Exception e) {
            throw new AuraHandledException(
                'No fue posible iniciar la eliminacion de object mapping: ' + e.getMessage()
            );
        }

        SaveObjectMappingResultDto response = new SaveObjectMappingResultDto();
        response.success = true;
        response.developerName = normalizedDeveloperName;
        response.deploymentId = deploymentId;
        response.deploymentStatus = 'Queued';
        response.message = 'Eliminacion enviada correctamente. Deployment Id: ' + deploymentId;
        return response;
    }

    @AuraEnabled
    public static SaveObjectMappingResultDto deleteObjectMapping(String developerName) {
        if (String.isBlank(developerName)) {
            throw new AuraHandledException('Developer Name es obligatorio para borrar mapping.');
        }

        String normalizedDeveloperName = normalizeMetadataToken(developerName);

        if (Test.isRunningTest()) {
            SaveObjectMappingResultDto simulated = new SaveObjectMappingResultDto();
            simulated.success = true;
            simulated.developerName = normalizedDeveloperName;
            simulated.deploymentStatus = 'Simulated';
            simulated.message = 'Validacion completada en prueba. Despliegue de metadata omitido.';
            return simulated;
        }

        Payment_Link_Object_Mapping__mdt existing = findObjectMappingOrNull(normalizedDeveloperName);
        if (existing == null) {
            throw new AuraHandledException(
                'No existe object mapping con Developer Name: ' + normalizedDeveloperName + '.'
            );
        }

        Metadata.CustomMetadata metadataRecord = buildObjectMappingMetadataRecord(
            existing.DeveloperName,
            buildDeletedObjectMappingLabel(existing.MasterLabel, existing.DeveloperName),
            existing.Object_API_Name__c,
            existing.Reference_Field__c,
            existing.Amount_Field__c,
            existing.Currency__c,
            existing.Workspace__c,
            false
        );

        Metadata.DeployContainer container = new Metadata.DeployContainer();
        container.addMetadata(metadataRecord);

        Id deploymentId;
        try {
            deploymentId = Metadata.Operations.enqueueDeployment(container, new NoopDeployCallback());
        } catch (Exception e) {
            throw new AuraHandledException(
                'No fue posible iniciar el borrado de object mapping: ' + e.getMessage()
            );
        }

        SaveObjectMappingResultDto response = new SaveObjectMappingResultDto();
        response.success = true;
        response.developerName = normalizedDeveloperName;
        response.deploymentId = deploymentId;
        response.deploymentStatus = 'Queued';
        response.message = 'Borrado enviado correctamente. Deployment Id: ' + deploymentId;
        return response;
    }

    @AuraEnabled
    public static List<MetadataFieldConfigDto> getMetadataFieldConfigs(String workspaceKey) {
        List<Payment_Link_Metadata_Field__mdt> records;

        if (String.isBlank(workspaceKey)) {
            records = [
                SELECT
                    DeveloperName,
                    Workspace__c,
                    Field_Label__c,
                    Field_API_Name__c,
                    Data_Type__c,
                    Required__c,
                    Xml_Tag__c,
                    Sort_Order__c,
                    Active__c
                FROM Payment_Link_Metadata_Field__mdt
                ORDER BY Workspace__c ASC, Sort_Order__c ASC, MasterLabel ASC
            ];
        } else {
            String normalizedWorkspace = workspaceKey.trim();
            records = [
                SELECT
                    DeveloperName,
                    Workspace__c,
                    Field_Label__c,
                    Field_API_Name__c,
                    Data_Type__c,
                    Required__c,
                    Xml_Tag__c,
                    Sort_Order__c,
                    Active__c
                FROM Payment_Link_Metadata_Field__mdt
                WHERE Workspace__c = :normalizedWorkspace
                ORDER BY Sort_Order__c ASC, MasterLabel ASC
            ];
        }

        List<MetadataFieldConfigDto> output = new List<MetadataFieldConfigDto>();
        for (Payment_Link_Metadata_Field__mdt row : records) {
            MetadataFieldConfigDto dto = new MetadataFieldConfigDto();
            dto.developerName = row.DeveloperName;
            dto.workspace = row.Workspace__c;
            dto.fieldLabel = row.Field_Label__c;
            dto.fieldApiName = row.Field_API_Name__c;
            dto.dataType = row.Data_Type__c;
            dto.required = row.Required__c;
            dto.xmlTag = row.Xml_Tag__c;
            dto.sortOrder = row.Sort_Order__c == null ? null : row.Sort_Order__c.intValue();
            dto.active = row.Active__c;
            output.add(dto);
        }

        return output;
    }

    @AuraEnabled
    public static List<WorkspaceOptionDto> getMetadataWorkspaceOptions() {
        Set<String> workspaceKeys = new Set<String>();
        workspaceKeys.add(DEFAULT_CONFIG_NAME);

        for (PagosOnline_Config__mdt cfg : [
            SELECT DeveloperName
            FROM PagosOnline_Config__mdt
            ORDER BY DeveloperName ASC
        ]) {
            if (!String.isBlank(cfg.DeveloperName)) {
                workspaceKeys.add(cfg.DeveloperName.trim());
            }
        }

        for (Payment_Link_Object_Mapping__mdt mappingCfg : [
            SELECT Workspace__c
            FROM Payment_Link_Object_Mapping__mdt
            WHERE Workspace__c != null
            ORDER BY Workspace__c ASC
        ]) {
            if (!String.isBlank(mappingCfg.Workspace__c)) {
                workspaceKeys.add(mappingCfg.Workspace__c.trim());
            }
        }

        for (Payment_Link_Metadata_Field__mdt fieldCfg : [
            SELECT Workspace__c
            FROM Payment_Link_Metadata_Field__mdt
            WHERE Workspace__c != null
            ORDER BY Workspace__c ASC
        ]) {
            if (!String.isBlank(fieldCfg.Workspace__c)) {
                workspaceKeys.add(fieldCfg.Workspace__c.trim());
            }
        }

        List<String> sortedKeys = new List<String>();
        sortedKeys.addAll(workspaceKeys);
        sortedKeys.sort();

        List<WorkspaceOptionDto> options = new List<WorkspaceOptionDto>();
        for (String key : sortedKeys) {
            WorkspaceOptionDto option = new WorkspaceOptionDto();
            option.label = key;
            option.value = key;
            options.add(option);
        }

        return options;
    }

    @AuraEnabled
    public static SaveMetadataFieldConfigResultDto saveMetadataFieldConfig(MetadataFieldConfigDto request) {
        System.debug(
            LoggingLevel.INFO,
            'GetNetPaymentUiFacade.saveMetadataFieldConfig payload=' + JSON.serialize(request)
        );

        if (request == null) {
            throw new AuraHandledException('La configuracion de metadata es obligatoria.');
        }

        validateMetadataConfigRequest(request);

        String normalizedWorkspace = request.workspace.trim();
        String normalizedFieldApiName = normalizeMetadataApiName(request.fieldApiName);
        String normalizedDeveloperName = normalizeMetadataDeveloperName(
            request.developerName,
            normalizedWorkspace,
            normalizedFieldApiName
        );
        String normalizedDataType = normalizeMetadataDataType(request.dataType);
        String normalizedFieldLabel = normalizeMetadataLabel(request.fieldLabel);
        String normalizedXmlTag = String.isBlank(request.xmlTag) ? normalizedFieldApiName : request.xmlTag.trim();
        Boolean activeValue = request.active == null ? true : request.active;
        Boolean requiredValue = request.required == true;

        Payment_Link_Metadata_Field__mdt existing = findMetadataFieldDefinitionOrNull(normalizedDeveloperName);

        Metadata.CustomMetadata metadataRecord = new Metadata.CustomMetadata();
        metadataRecord.fullName = 'Payment_Link_Metadata_Field__mdt.' + normalizedDeveloperName;
        metadataRecord.label = normalizedFieldLabel;

        addMetadataValue(metadataRecord, 'Workspace__c', normalizedWorkspace);
        addMetadataValue(metadataRecord, 'Field_Label__c', normalizedFieldLabel);
        addMetadataValue(metadataRecord, 'Field_API_Name__c', normalizedFieldApiName);
        addMetadataValue(metadataRecord, 'Data_Type__c', normalizedDataType);
        addMetadataValue(metadataRecord, 'Required__c', requiredValue);
        addMetadataValue(metadataRecord, 'Xml_Tag__c', normalizedXmlTag);
        addMetadataValue(metadataRecord, 'Active__c', activeValue);

        if (request.sortOrder != null) {
            addMetadataValue(metadataRecord, 'Sort_Order__c', request.sortOrder);
        } else if (existing != null && existing.Sort_Order__c != null) {
            addMetadataValue(metadataRecord, 'Sort_Order__c', existing.Sort_Order__c.intValue());
        }

        if (Test.isRunningTest()) {
            SaveMetadataFieldConfigResultDto simulated = new SaveMetadataFieldConfigResultDto();
            simulated.success = true;
            simulated.developerName = normalizedDeveloperName;
            simulated.deploymentStatus = 'Simulated';
            simulated.message = 'Validacion completada en prueba. Despliegue de metadata omitido.';
            return simulated;
        }

        Metadata.DeployContainer container = new Metadata.DeployContainer();
        container.addMetadata(metadataRecord);

        Id deploymentId;
        try {
            deploymentId = Metadata.Operations.enqueueDeployment(container, new NoopDeployCallback());
        } catch (Exception e) {
            throw new AuraHandledException(
                'No fue posible iniciar el guardado de metadata: ' + e.getMessage()
            );
        }

        SaveMetadataFieldConfigResultDto response = new SaveMetadataFieldConfigResultDto();
        response.success = true;
        response.developerName = normalizedDeveloperName;
        response.deploymentId = deploymentId;
        response.deploymentStatus = 'Queued';
        response.message = 'Guardado enviado correctamente. Deployment Id: ' + deploymentId;
        return response;
    }

    @AuraEnabled
    public static SaveMetadataFieldConfigResultDto saveMetadataFieldConfigDirect(
        String developerName,
        String workspace,
        String fieldLabel,
        String fieldApiName,
        String dataType,
        Boolean required,
        String xmlTag,
        Integer sortOrder,
        Boolean active
    ) {
        System.debug(
            LoggingLevel.INFO,
            'GetNetPaymentUiFacade.saveMetadataFieldConfigDirect payload=' +
            JSON.serialize(
                new Map<String, Object>{
                    'developerName' => developerName,
                    'workspace' => workspace,
                    'fieldLabel' => fieldLabel,
                    'fieldApiName' => fieldApiName,
                    'dataType' => dataType,
                    'required' => required,
                    'xmlTag' => xmlTag,
                    'sortOrder' => sortOrder,
                    'active' => active
                }
            )
        );

        MetadataFieldConfigDto request = new MetadataFieldConfigDto();
        request.developerName = developerName;
        request.workspace = workspace;
        request.fieldLabel = fieldLabel;
        request.fieldApiName = fieldApiName;
        request.dataType = dataType;
        request.required = required;
        request.xmlTag = xmlTag;
        request.sortOrder = sortOrder;
        request.active = active;
        return saveMetadataFieldConfig(request);
    }

    @AuraEnabled
    public static SaveMetadataFieldConfigResultDto deactivateMetadataFieldConfig(String developerName) {
        if (String.isBlank(developerName)) {
            throw new AuraHandledException('Developer Name es obligatorio para desactivar.');
        }

        String normalizedDeveloperName = normalizeMetadataToken(developerName);
        Payment_Link_Metadata_Field__mdt existing = findMetadataFieldDefinitionOrNull(normalizedDeveloperName);
        if (existing == null) {
            throw new AuraHandledException('No existe configuracion con Developer Name: ' + normalizedDeveloperName + '.');
        }

        Metadata.CustomMetadata metadataRecord = new Metadata.CustomMetadata();
        metadataRecord.fullName = 'Payment_Link_Metadata_Field__mdt.' + normalizedDeveloperName;
        metadataRecord.label = String.isBlank(existing.MasterLabel) ? normalizedDeveloperName : existing.MasterLabel;

        addMetadataValue(metadataRecord, 'Workspace__c', existing.Workspace__c);
        addMetadataValue(metadataRecord, 'Field_Label__c', existing.Field_Label__c);
        addMetadataValue(metadataRecord, 'Field_API_Name__c', existing.Field_API_Name__c);
        addMetadataValue(metadataRecord, 'Data_Type__c', existing.Data_Type__c);
        addMetadataValue(metadataRecord, 'Required__c', existing.Required__c);
        addMetadataValue(metadataRecord, 'Xml_Tag__c', existing.Xml_Tag__c);
        addMetadataValue(metadataRecord, 'Active__c', false);
        if (existing.Sort_Order__c != null) {
            addMetadataValue(metadataRecord, 'Sort_Order__c', existing.Sort_Order__c.intValue());
        }

        if (Test.isRunningTest()) {
            SaveMetadataFieldConfigResultDto simulated = new SaveMetadataFieldConfigResultDto();
            simulated.success = true;
            simulated.developerName = normalizedDeveloperName;
            simulated.deploymentStatus = 'Simulated';
            simulated.message = 'Validacion completada en prueba. Despliegue de metadata omitido.';
            return simulated;
        }

        Metadata.DeployContainer container = new Metadata.DeployContainer();
        container.addMetadata(metadataRecord);

        Id deploymentId;
        try {
            deploymentId = Metadata.Operations.enqueueDeployment(container, new NoopDeployCallback());
        } catch (Exception e) {
            throw new AuraHandledException(
                'No fue posible iniciar la desactivacion de metadata: ' + e.getMessage()
            );
        }

        SaveMetadataFieldConfigResultDto response = new SaveMetadataFieldConfigResultDto();
        response.success = true;
        response.developerName = normalizedDeveloperName;
        response.deploymentId = deploymentId;
        response.deploymentStatus = 'Queued';
        response.message = 'Desactivacion enviada correctamente. Deployment Id: ' + deploymentId;
        return response;
    }

    @AuraEnabled
    public static List<WorkspaceOptionDto> getWorkspaceOptions() {
        Set<String> workspaceKeys = new Set<String>();
        workspaceKeys.add(DEFAULT_CONFIG_NAME);

        for (PagosOnline_Config__mdt cfg : [
            SELECT DeveloperName
            FROM PagosOnline_Config__mdt
            ORDER BY DeveloperName ASC
        ]) {
            if (!String.isBlank(cfg.DeveloperName)) {
                workspaceKeys.add(cfg.DeveloperName.trim());
            }
        }

        for (Payment_Link_Metadata_Field__mdt fieldCfg : [
            SELECT Workspace__c
            FROM Payment_Link_Metadata_Field__mdt
            WHERE Active__c = true AND Workspace__c != null
            ORDER BY Workspace__c ASC
        ]) {
            if (!String.isBlank(fieldCfg.Workspace__c)) {
                workspaceKeys.add(fieldCfg.Workspace__c.trim());
            }
        }

        List<String> sortedKeys = new List<String>();
        sortedKeys.addAll(workspaceKeys);
        sortedKeys.sort();

        List<WorkspaceOptionDto> options = new List<WorkspaceOptionDto>();
        for (String key : sortedKeys) {
            WorkspaceOptionDto option = new WorkspaceOptionDto();
            option.label = key;
            option.value = key;
            options.add(option);
        }

        return options;
    }

    @AuraEnabled
    public static List<PaymentLinkMetadataService.MetadataFieldDefinitionDto> getQuickPaymentFieldDefinitions(
        String workspaceKey
    ) {
        return PaymentLinkMetadataService.getFieldDefinitions(workspaceKey);
    }

    @AuraEnabled
    public static QuickPaymentResultDto generateQuickPayment(QuickPaymentRequestDto request) {
        if (request == null) {
            throw new AuraHandledException('La solicitud de Quick Payment es obligatoria.');
        }

        validateQuickPaymentRequest(request);

        String normalizedReference = request.reference.trim();
        String resolvedWorkspace = request.workspace.trim();
        String resolvedCurrency = normalizeCurrencyCode(request.currencyCode);

        Payment_Link__c existing = findPaymentLinkByReference(normalizedReference);
        if (existing != null) {
            QuickPaymentResultDto existingResponse = new QuickPaymentResultDto();
            existingResponse.paymentLinkId = existing.Id;
            existingResponse.paymentUrl = existing.Payment_URL__c;
            existingResponse.status = existing.Status__c;
            existingResponse.workspace = existing.Workspace__c;
            existingResponse.currencyCode = existing.Currency__c;
            existingResponse.metadataJson = existing.Metadata_JSON__c;
            existingResponse.metadataIndex = existing.Metadata_Index__c;
            existingResponse.wasExisting = true;
            existingResponse.message =
                'Ya existe una liga para la referencia "' + normalizedReference + '". Se devuelve la liga existente.';
            return existingResponse;
        }

        Payment_Link__c paymentLinkDraft = new Payment_Link__c(
            Reference__c = normalizedReference,
            Amount__c = request.amount,
            Concept__c = request.concept.trim(),
            Customer_Name__c = request.customerName.trim(),
            Workspace__c = resolvedWorkspace,
            Currency__c = resolvedCurrency,
            Metadata_JSON__c = request.metadataJson,
            Status__c = 'Draft'
        );

        if (Test.isRunningTest()) {
            insert paymentLinkDraft;
            PaymentLinkMetadataService.saveMetadata(paymentLinkDraft.Id, request.metadataJson);

            paymentLinkDraft.Status__c = 'Pending';
            paymentLinkDraft.Payment_URL__c = 'https://example.test/pay/' + String.valueOf(paymentLinkDraft.Id);
            update paymentLinkDraft;

            Payment_Link__c simulated = [
                SELECT Id, Payment_URL__c, Status__c, Workspace__c, Currency__c, Metadata_JSON__c, Metadata_Index__c
                FROM Payment_Link__c
                WHERE Id = :paymentLinkDraft.Id
                LIMIT 1
            ];

            QuickPaymentResultDto simulatedResponse = new QuickPaymentResultDto();
            simulatedResponse.paymentLinkId = simulated.Id;
            simulatedResponse.paymentUrl = simulated.Payment_URL__c;
            simulatedResponse.status = simulated.Status__c;
            simulatedResponse.workspace = simulated.Workspace__c;
            simulatedResponse.currencyCode = simulated.Currency__c;
            simulatedResponse.metadataJson = simulated.Metadata_JSON__c;
            simulatedResponse.metadataIndex = simulated.Metadata_Index__c;
            simulatedResponse.wasExisting = false;
            simulatedResponse.message = 'Quick Payment simulado en prueba.';
            return simulatedResponse;
        }

        // Important: callout must run before DML in this transaction.
        Payment_Link__c generated = PaymentLinkService.generateLinkFromDraft(paymentLinkDraft);

        QuickPaymentResultDto response = new QuickPaymentResultDto();
        response.paymentLinkId = generated.Id;
        response.paymentUrl = generated.Payment_URL__c;
        response.status = generated.Status__c;
        response.workspace = generated.Workspace__c;
        response.currencyCode = generated.Currency__c;
        response.metadataJson = generated.Metadata_JSON__c;
        response.metadataIndex = generated.Metadata_Index__c;
        response.wasExisting = false;
        response.message = 'Liga generada correctamente.';
        return response;
    }

    @AuraEnabled
    public static QuickPaymentResultDto generateQuickPaymentDirect(
        String reference,
        Decimal amount,
        String currencyCode,
        String concept,
        String customerName,
        String workspace,
        String metadataJson
    ) {
        QuickPaymentRequestDto request = new QuickPaymentRequestDto();
        request.reference = reference;
        request.amount = amount;
        request.currencyCode = currencyCode;
        request.concept = concept;
        request.customerName = customerName;
        request.workspace = workspace;
        request.metadataJson = metadataJson;
        return generateQuickPayment(request);
    }

    private static void validateAuthorizationRequest(AuthorizationConfigDto request) {
        validateRequiredText('Company ID', request.companyId);
        validateRequiredText('Branch ID', request.branchId);
        validateRequiredText('User', request.user);
        validateRequiredText('Password', request.password);
        validateRequiredText('Encryption Key', request.encryptionKey);
        validateRequiredText('Data0', request.data0);

        String key = request.encryptionKey == null ? '' : request.encryptionKey.trim();
        if (!Pattern.compile('^[A-Fa-f0-9]{32}$').matcher(key).matches()) {
            throw new AuraHandledException('Encryption Key debe ser hexadecimal de 32 caracteres.');
        }
    }

    private static void validateRequiredText(String label, String value) {
        if (String.isBlank(value)) {
            throw new AuraHandledException(label + ' es obligatorio.');
        }
    }

    private static void validateQuickPaymentRequest(QuickPaymentRequestDto request) {
        validateRequiredText('Reference', request.reference);
        validateRequiredText('Concept', request.concept);
        validateRequiredText('Customer Name', request.customerName);
        validateRequiredText('Workspace', request.workspace);

        if (request.amount == null || request.amount <= 0) {
            throw new AuraHandledException('Amount debe ser mayor a cero.');
        }

        normalizeCurrencyCode(request.currencyCode);
    }

    private static String normalizeCurrencyCode(String currencyCode) {
        if (String.isBlank(currencyCode)) {
            return DEFAULT_CURRENCY;
        }

        String normalized = currencyCode.trim().toUpperCase();
        if (!Pattern.compile('^[A-Z]{3}$').matcher(normalized).matches()) {
            throw new AuraHandledException('Currency debe tener formato ISO de 3 letras (ejemplo: MXN).');
        }
        return normalized;
    }

    private static void validateMetadataConfigRequest(MetadataFieldConfigDto request) {
        validateRequiredText('Workspace', request.workspace);
        validateRequiredText('Field Label', request.fieldLabel);
        validateRequiredText('Field API Name', request.fieldApiName);
        validateRequiredText('Data Type', request.dataType);

        if (request.sortOrder != null && request.sortOrder < 0) {
            throw new AuraHandledException('Sort Order no puede ser negativo.');
        }

        normalizeMetadataApiName(request.fieldApiName);
        normalizeMetadataDataType(request.dataType);
    }

    private static String normalizeMetadataApiName(String apiName) {
        String token = normalizeMetadataToken(apiName);
        if (!Pattern.compile('^[A-Za-z][A-Za-z0-9_]*$').matcher(token).matches()) {
            throw new AuraHandledException(
                'Field API Name invalido. Usa solo letras, numeros y guion bajo, iniciando con letra.'
            );
        }
        return token;
    }

    private static String normalizeMetadataDataType(String dataType) {
        String token = normalizeMetadataToken(dataType).toLowerCase();
        if (token == 'text') {
            return 'Text';
        }
        if (token == 'number') {
            return 'Number';
        }
        if (token == 'date') {
            return 'Date';
        }
        if (token == 'boolean') {
            return 'Boolean';
        }

        throw new AuraHandledException('Data Type invalido. Usa Text, Number, Date o Boolean.');
    }

    private static String normalizeMetadataDeveloperName(
        String developerName,
        String workspace,
        String fieldApiName
    ) {
        if (!String.isBlank(developerName)) {
            String explicitName = normalizeMetadataToken(developerName);
            if (explicitName.length() > MAX_METADATA_DEVELOPER_NAME_LENGTH) {
                explicitName = explicitName.substring(0, MAX_METADATA_DEVELOPER_NAME_LENGTH);
            }
            if (!Pattern.compile('^[A-Za-z].*$').matcher(explicitName).matches()) {
                throw new AuraHandledException('Developer Name debe iniciar con letra.');
            }
            return explicitName;
        }

        String base = workspace + '_' + fieldApiName;
        String generated = normalizeMetadataToken(base);
        if (generated.length() > MAX_METADATA_DEVELOPER_NAME_LENGTH) {
            generated = generated.substring(0, MAX_METADATA_DEVELOPER_NAME_LENGTH);
        }
        if (!Pattern.compile('^[A-Za-z].*$').matcher(generated).matches()) {
            generated = 'M_' + generated;
            if (generated.length() > MAX_METADATA_DEVELOPER_NAME_LENGTH) {
                generated = generated.substring(0, MAX_METADATA_DEVELOPER_NAME_LENGTH);
            }
        }
        return generated;
    }

    private static String normalizeMetadataLabel(String label) {
        String normalized = String.isBlank(label) ? '' : label.trim();
        if (String.isBlank(normalized)) {
            throw new AuraHandledException('Field Label es obligatorio.');
        }
        if (normalized.length() > MAX_METADATA_LABEL_LENGTH) {
            return normalized.substring(0, MAX_METADATA_LABEL_LENGTH);
        }
        return normalized;
    }

    private static String normalizeMetadataToken(String value) {
        String token = String.isBlank(value) ? '' : value.trim();
        token = token.replace(' ', '_').replace('-', '_');
        token = token.replaceAll('[^A-Za-z0-9_]', '_');
        while (token.contains('__')) {
            token = token.replace('__', '_');
        }

        if (String.isBlank(token)) {
            throw new AuraHandledException('Se requiere un valor valido para identificador.');
        }

        return token;
    }

    private static String normalizeComparisonKey(String value) {
        return String.isBlank(value) ? '' : value.trim().toLowerCase();
    }

    private static Boolean isObjectEligibleForMapping(Schema.DescribeSObjectResult objectDescribe) {
        return objectDescribe != null &&
            objectDescribe.isAccessible() &&
            objectDescribe.isQueryable() &&
            !objectDescribe.isCustomSetting() &&
            !objectDescribe.isDeprecatedAndHidden();
    }

    private static Boolean isObjectAllowedForMapping(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            return false;
        }

        String normalizedObjectApiName = objectApiName.trim();
        if (OBJECT_MAPPING_ALLOWED_STANDARD_OBJECTS.contains(normalizedObjectApiName)) {
            return true;
        }

        return normalizedObjectApiName.endsWith(CUSTOM_OBJECT_SUFFIX);
    }

    private static Boolean hasMappingReferenceField(Map<String, Schema.SObjectField> fields) {
        if (fields == null || fields.isEmpty()) {
            return false;
        }

        for (Schema.SObjectField sobjectField : fields.values()) {
            Schema.DescribeFieldResult fieldDescribe = sobjectField.getDescribe();
            if (fieldDescribe.isAccessible() && isReferenceMappingFieldType(fieldDescribe.getType())) {
                return true;
            }
        }
        return false;
    }

    private static Boolean hasMappingAmountField(Map<String, Schema.SObjectField> fields) {
        if (fields == null || fields.isEmpty()) {
            return false;
        }

        for (Schema.SObjectField sobjectField : fields.values()) {
            Schema.DescribeFieldResult fieldDescribe = sobjectField.getDescribe();
            if (fieldDescribe.isAccessible() && isAmountMappingFieldType(fieldDescribe.getType())) {
                return true;
            }
        }
        return false;
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

    private static WorkspaceOptionDto buildMappingFieldOption(String fieldApiName, String fieldLabel) {
        WorkspaceOptionDto option = new WorkspaceOptionDto();
        option.value = fieldApiName;
        option.label = String.isBlank(fieldLabel)
            ? fieldApiName
            : fieldLabel + ' (' + fieldApiName + ')';
        return option;
    }

    private static Schema.DescribeSObjectResult getObjectDescribeOrThrow(String objectApiName) {
        String normalizedObjectApiName = objectApiName == null ? '' : objectApiName.trim();
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        if (!globalDescribe.containsKey(normalizedObjectApiName)) {
            throw new AuraHandledException('Object invalido para mapping: ' + normalizedObjectApiName + '.');
        }

        return globalDescribe.get(normalizedObjectApiName).getDescribe();
    }

    private static void validateObjectMappingFields(
        String objectApiName,
        String referenceField,
        String amountField
    ) {
        Schema.DescribeSObjectResult objectDescribe = getObjectDescribeOrThrow(objectApiName);
        Map<String, Schema.SObjectField> fieldMap = objectDescribe.fields.getMap();

        if (!fieldMap.containsKey(referenceField)) {
            throw new AuraHandledException('Reference Field invalido para objeto ' + objectApiName + '.');
        }
        if (!fieldMap.containsKey(amountField)) {
            throw new AuraHandledException('Amount Field invalido para objeto ' + objectApiName + '.');
        }

        Schema.DescribeFieldResult referenceDescribe = fieldMap.get(referenceField).getDescribe();
        Schema.DescribeFieldResult amountDescribe = fieldMap.get(amountField).getDescribe();

        if (!isReferenceMappingFieldType(referenceDescribe.getType())) {
            throw new AuraHandledException('Reference Field debe ser un campo valido para referencia.');
        }
        if (!isAmountMappingFieldType(amountDescribe.getType())) {
            throw new AuraHandledException('Amount Field debe ser numerico o currency.');
        }
    }

    private static String normalizeObjectMappingCurrency(String currencyCode) {
        String normalized = currencyCode == null ? '' : currencyCode.trim().toUpperCase();
        if (normalized != 'MXN' && normalized != 'USD') {
            throw new AuraHandledException('Currency invalido. Usa MXN o USD.');
        }
        return normalized;
    }

    private static String resolveObjectMappingDeveloperName(
        String incomingDeveloperName,
        String objectApiName,
        String workspace
    ) {
        if (!String.isBlank(incomingDeveloperName)) {
            String normalized = normalizeMetadataToken(incomingDeveloperName);
            if (normalized.length() > MAX_METADATA_DEVELOPER_NAME_LENGTH) {
                normalized = normalized.substring(0, MAX_METADATA_DEVELOPER_NAME_LENGTH);
            }
            return normalized;
        }

        return buildUniqueObjectMappingDeveloperName(objectApiName, workspace);
    }

    private static String buildUniqueObjectMappingDeveloperName(String objectApiName, String workspace) {
        String normalizedObject = normalizeMetadataToken(objectApiName);
        String normalizedWorkspace = normalizeMetadataToken(workspace);
        String base = 'MAP_' + normalizedObject + '_' + normalizedWorkspace;

        Set<String> existingNames = new Set<String>();
        for (Payment_Link_Object_Mapping__mdt row : [
            SELECT DeveloperName
            FROM Payment_Link_Object_Mapping__mdt
            WHERE Object_API_Name__c = :objectApiName
            ORDER BY DeveloperName ASC
        ]) {
            existingNames.add(row.DeveloperName);
        }

        String baseCandidate = base.length() > MAX_METADATA_DEVELOPER_NAME_LENGTH
            ? base.substring(0, MAX_METADATA_DEVELOPER_NAME_LENGTH)
            : base;
        if (!existingNames.contains(baseCandidate)) {
            return baseCandidate;
        }

        for (Integer index = 1; index <= 9999; index++) {
            String suffix = '_' + String.valueOf(index).leftPad(4, '0');
            Integer maxBaseLength = MAX_METADATA_DEVELOPER_NAME_LENGTH - suffix.length();
            String truncatedBase = base.length() > maxBaseLength ? base.substring(0, maxBaseLength) : base;
            String candidate = truncatedBase + suffix;
            if (!existingNames.contains(candidate)) {
                return candidate;
            }
        }

        throw new AuraHandledException('No fue posible generar un Developer Name unico para el mapping.');
    }

    private static List<Payment_Link_Object_Mapping__mdt> findObjectMappingsByObjectWorkspace(
        String objectApiName,
        String workspace
    ) {
        String normalizedWorkspace = normalizeComparisonKey(workspace);
        List<Payment_Link_Object_Mapping__mdt> output = new List<Payment_Link_Object_Mapping__mdt>();
        for (Payment_Link_Object_Mapping__mdt row : [
            SELECT
                DeveloperName,
                MasterLabel,
                Object_API_Name__c,
                Reference_Field__c,
                Amount_Field__c,
                Currency__c,
                Workspace__c,
                Active__c
            FROM Payment_Link_Object_Mapping__mdt
            WHERE Object_API_Name__c = :objectApiName
            ORDER BY DeveloperName ASC
        ]) {
            if (normalizeComparisonKey(row.Workspace__c) == normalizedWorkspace) {
                output.add(row);
            }
        }
        return output;
    }

    private static Metadata.CustomMetadata buildObjectMappingMetadataRecord(
        String developerName,
        String label,
        String objectApiName,
        String referenceField,
        String amountField,
        String currencyCode,
        String workspace,
        Boolean active
    ) {
        Metadata.CustomMetadata metadataRecord = new Metadata.CustomMetadata();
        metadataRecord.fullName = 'Payment_Link_Object_Mapping__mdt.' + developerName;
        metadataRecord.label = String.isBlank(label) ? developerName : label;

        addMetadataValue(metadataRecord, 'Object_API_Name__c', objectApiName);
        addMetadataValue(metadataRecord, 'Reference_Field__c', referenceField);
        addMetadataValue(metadataRecord, 'Amount_Field__c', amountField);
        addMetadataValue(metadataRecord, 'Currency__c', currencyCode);
        addMetadataValue(metadataRecord, 'Workspace__c', workspace);
        addMetadataValue(metadataRecord, 'Active__c', active == true);
        return metadataRecord;
    }

    private static String truncateObjectMappingLabel(String label) {
        String normalized = String.isBlank(label) ? 'Object Mapping' : label.trim();
        if (normalized.length() > MAX_METADATA_LABEL_LENGTH) {
            return normalized.substring(0, MAX_METADATA_LABEL_LENGTH);
        }
        return normalized;
    }

    private static String buildDeletedObjectMappingLabel(String existingLabel, String developerName) {
        String baseLabel = String.isBlank(existingLabel) ? developerName : existingLabel;
        String deletedLabel = OBJECT_MAPPING_DELETED_LABEL_PREFIX + baseLabel;
        if (deletedLabel.length() > MAX_METADATA_LABEL_LENGTH) {
            return deletedLabel.substring(0, MAX_METADATA_LABEL_LENGTH);
        }
        return deletedLabel;
    }

    private static Boolean isDeletedObjectMappingLabel(String label) {
        if (String.isBlank(label)) {
            return false;
        }
        return label.startsWith(OBJECT_MAPPING_DELETED_LABEL_PREFIX);
    }

    private static String resolveConfigName(String configName) {
        if (!String.isBlank(configName)) {
            return configName.trim();
        }
        return DEFAULT_CONFIG_NAME;
    }

    private static PagosOnline_Config__mdt findConfigOrNull(String developerName) {
        List<PagosOnline_Config__mdt> rows = [
            SELECT
                DeveloperName,
                MasterLabel,
                CompanyId__c,
                BranchId__c,
                User__c,
                Password__c,
                AESKeyHex__c,
                Data0__c,
                GeneratePath__c,
                TimeoutMs__c,
                MaxRetries__c
            FROM PagosOnline_Config__mdt
            WHERE DeveloperName = :developerName
            LIMIT 1
        ];

        return rows.isEmpty() ? null : rows[0];
    }

    private static Payment_Link_Metadata_Field__mdt findMetadataFieldDefinitionOrNull(String developerName) {
        List<Payment_Link_Metadata_Field__mdt> rows = [
            SELECT
                DeveloperName,
                MasterLabel,
                Workspace__c,
                Field_Label__c,
                Field_API_Name__c,
                Data_Type__c,
                Required__c,
                Xml_Tag__c,
                Sort_Order__c,
                Active__c
            FROM Payment_Link_Metadata_Field__mdt
            WHERE DeveloperName = :developerName
            LIMIT 1
        ];

        return rows.isEmpty() ? null : rows[0];
    }

    private static Payment_Link_Object_Mapping__mdt findObjectMappingOrNull(String developerName) {
        List<Payment_Link_Object_Mapping__mdt> rows = [
            SELECT
                DeveloperName,
                MasterLabel,
                Object_API_Name__c,
                Reference_Field__c,
                Amount_Field__c,
                Currency__c,
                Workspace__c,
                Active__c
            FROM Payment_Link_Object_Mapping__mdt
            WHERE DeveloperName = :developerName
            LIMIT 1
        ];

        return rows.isEmpty() ? null : rows[0];
    }

    private static Payment_Link__c findPaymentLinkByReference(String reference) {
        if (String.isBlank(reference)) {
            return null;
        }

        List<Payment_Link__c> rows = [
            SELECT Id, Payment_URL__c, Status__c, Workspace__c, Currency__c, Metadata_JSON__c, Metadata_Index__c
            FROM Payment_Link__c
            WHERE Reference__c = :reference
            LIMIT 1
        ];

        return rows.isEmpty() ? null : rows[0];
    }

    private static void addMetadataValue(Metadata.CustomMetadata record, String fieldApiName, Object fieldValue) {
        Metadata.CustomMetadataValue field = new Metadata.CustomMetadataValue();
        field.field = fieldApiName;
        field.value = fieldValue;
        record.values.add(field);
    }

}
