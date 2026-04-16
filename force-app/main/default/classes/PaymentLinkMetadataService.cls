public with sharing class PaymentLinkMetadataService {
    private static final String DATA_TYPE_TEXT = 'Text';
    private static final String DATA_TYPE_NUMBER = 'Number';
    private static final String DATA_TYPE_DATE = 'Date';
    private static final String DATA_TYPE_BOOLEAN = 'Boolean';
    private static final Integer MAX_LONG_TEXT_LENGTH = 32768;
    private static final Integer MAX_DISPLAY_VALUE_LENGTH = 255;

    @TestVisible
    private static List<FieldDefinition> definitionOverrides;

    public class FieldDefinition implements Comparable {
        public String apiName;
        public String label;
        public String dataType;
        public Boolean required;
        public Boolean active;
        public String xmlTag;
        public Integer sortOrder;
        public String workspace;

        public FieldDefinition() {
        }

        public FieldDefinition(
            String apiName,
            String label,
            String dataType,
            Boolean required,
            Boolean active,
            String xmlTag,
            Integer sortOrder,
            String workspace
        ) {
            this.apiName = apiName;
            this.label = label;
            this.dataType = dataType;
            this.required = required;
            this.active = active;
            this.xmlTag = xmlTag;
            this.sortOrder = sortOrder;
            this.workspace = workspace;
        }

        public Integer compareTo(Object otherObject) {
            FieldDefinition other = (FieldDefinition) otherObject;
            Integer leftOrder = sortOrder == null ? 999999 : sortOrder;
            Integer rightOrder = other.sortOrder == null ? 999999 : other.sortOrder;

            if (leftOrder != rightOrder) {
                return leftOrder < rightOrder ? -1 : 1;
            }

            String leftLabel = String.isBlank(label) ? '' : label.toLowerCase();
            String rightLabel = String.isBlank(other.label) ? '' : other.label.toLowerCase();
            Integer labelCompare = leftLabel.compareTo(rightLabel);
            if (labelCompare != 0) {
                return labelCompare;
            }

            String leftApi = String.isBlank(apiName) ? '' : apiName.toLowerCase();
            String rightApi = String.isBlank(other.apiName) ? '' : other.apiName.toLowerCase();
            return leftApi.compareTo(rightApi);
        }
    }

    public class MetadataEntry {
        public String apiName;
        public String label;
        public String dataType;
        public String xmlTag;
        public String stringValue;
        public Decimal numberValue;
        public Date dateValue;
        public Boolean booleanValue;
        public Boolean isEmpty;
        public Object jsonValue;
    }

    public class MetadataBuildResult {
        public String metadataXml;
        public String normalizedJson;
        public String searchIndex;
        public List<MetadataEntry> entries;

        public MetadataBuildResult() {
            entries = new List<MetadataEntry>();
            metadataXml = '';
            normalizedJson = null;
            searchIndex = null;
        }
    }

    public class MetadataFieldDefinitionDto {
        @AuraEnabled
        public String apiName;

        @AuraEnabled
        public String label;

        @AuraEnabled
        public String dataType;

        @AuraEnabled
        public Boolean required;

        @AuraEnabled
        public String xmlTag;

        @AuraEnabled
        public Integer sortOrder;

        @AuraEnabled
        public String workspace;
    }

    public class SaveMetadataResultDto {
        @AuraEnabled
        public Id paymentLinkId;

        @AuraEnabled
        public String workspace;

        @AuraEnabled
        public String metadataJson;

        @AuraEnabled
        public String message;
    }

    @AuraEnabled(cacheable=true)
    public static List<MetadataFieldDefinitionDto> getFieldDefinitions(String workspaceKey) {
        List<MetadataFieldDefinitionDto> output = new List<MetadataFieldDefinitionDto>();
        for (FieldDefinition definition : loadDefinitions(workspaceKey)) {
            MetadataFieldDefinitionDto dto = new MetadataFieldDefinitionDto();
            dto.apiName = definition.apiName;
            dto.label = definition.label;
            dto.dataType = definition.dataType;
            dto.required = definition.required;
            dto.xmlTag = definition.xmlTag;
            dto.sortOrder = definition.sortOrder;
            dto.workspace = definition.workspace;
            output.add(dto);
        }
        return output;
    }

    @AuraEnabled(cacheable=true)
    public static String getMetadataJson(Id paymentLinkId) {
        if (paymentLinkId == null) {
            throw new AuraHandledException('El Id de Payment Link es obligatorio.');
        }

        Payment_Link__c link = [SELECT Metadata_JSON__c FROM Payment_Link__c WHERE Id = :paymentLinkId LIMIT 1];
        return link.Metadata_JSON__c;
    }

    @AuraEnabled
    public static SaveMetadataResultDto saveMetadata(Id paymentLinkId, String metadataJson) {
        if (paymentLinkId == null) {
            throw new AuraHandledException('El Id de Payment Link es obligatorio para guardar metadatos.');
        }

        Payment_Link__c link = [
            SELECT
                Id,
                Workspace__c,
                Amount__c,
                Reference__c,
                Concept__c,
                Customer_Name__c,
                Metadata_JSON__c,
                Metadata_Index__c
            FROM Payment_Link__c
            WHERE Id = :paymentLinkId
            LIMIT 1
            FOR UPDATE
        ];

        String workspaceKey = resolveWorkspaceKey(link.Workspace__c);
        Map<String, Object> rawValues = parseMetadataJson(metadataJson);
        MetadataBuildResult result = buildMetadata(link, workspaceKey, rawValues, false);

        link.Metadata_JSON__c = result.normalizedJson;
        link.Metadata_Index__c = result.searchIndex;

        try {
            update link;
            syncMetadataRows(link.Id, workspaceKey, result);
        } catch (DmlException e) {
            if (Test.isRunningTest()) {
                throw e;
            }
            throw new AuraHandledException('No se pudo guardar los metadatos de la liga: ' + e.getDmlMessage(0));
        }

        SaveMetadataResultDto response = new SaveMetadataResultDto();
        response.paymentLinkId = link.Id;
        response.workspace = workspaceKey;
        response.metadataJson = link.Metadata_JSON__c;
        response.message = 'Metadatos guardados correctamente.';
        return response;
    }

    public static MetadataBuildResult prepareForGeneration(Payment_Link__c paymentLink, String workspaceKey) {
        if (paymentLink == null) {
            throw new AuraHandledException('No se recibio el Payment Link para validar metadatos.');
        }

        Map<String, Object> rawValues = parseMetadataJson(paymentLink.Metadata_JSON__c);
        MetadataBuildResult result = buildMetadata(paymentLink, workspaceKey, rawValues, true);
        paymentLink.Metadata_JSON__c = result.normalizedJson;
        paymentLink.Metadata_Index__c = result.searchIndex;
        return result;
    }

    public static void syncMetadataRows(Id paymentLinkId, String workspaceKey, MetadataBuildResult buildResult) {
        if (paymentLinkId == null || buildResult == null) {
            return;
        }

        List<Payment_Link_Metadata__c> existingRows = [
            SELECT Id, Field_API_Name__c
            FROM Payment_Link_Metadata__c
            WHERE Payment_Link__c = :paymentLinkId
        ];

        Map<String, Payment_Link_Metadata__c> existingByKey = new Map<String, Payment_Link_Metadata__c>();
        for (Payment_Link_Metadata__c existing : existingRows) {
            existingByKey.put(normalizeKey(existing.Field_API_Name__c), existing);
        }

        List<Payment_Link_Metadata__c> rowsToUpsert = new List<Payment_Link_Metadata__c>();
        Set<String> activeKeys = new Set<String>();

        for (MetadataEntry entry : buildResult.entries) {
            String normalizedKey = normalizeKey(entry.apiName);
            activeKeys.add(normalizedKey);

            Payment_Link_Metadata__c row = existingByKey.containsKey(normalizedKey)
                ? existingByKey.get(normalizedKey)
                : new Payment_Link_Metadata__c();

            row.Payment_Link__c = paymentLinkId;
            row.Workspace__c = workspaceKey;
            row.Field_API_Name__c = entry.apiName;
            row.Field_Label__c = entry.label;
            row.Data_Type__c = entry.dataType;
            row.Value_Text__c = PolUtil.trimToMax(entry.stringValue, MAX_DISPLAY_VALUE_LENGTH);
            row.Display_Value__c = PolUtil.trimToMax(entry.stringValue, MAX_DISPLAY_VALUE_LENGTH);
            row.Value_Number__c = entry.numberValue;
            row.Value_Date__c = entry.dateValue;
            row.Value_Boolean__c = entry.booleanValue == null ? false : entry.booleanValue;
            row.Unique_Key__c = String.valueOf(paymentLinkId) + '|' + entry.apiName;

            rowsToUpsert.add(row);
        }

        List<Payment_Link_Metadata__c> rowsToDelete = new List<Payment_Link_Metadata__c>();
        for (Payment_Link_Metadata__c existing : existingRows) {
            if (!activeKeys.contains(normalizeKey(existing.Field_API_Name__c))) {
                rowsToDelete.add(existing);
            }
        }

        if (!rowsToUpsert.isEmpty()) {
            upsert rowsToUpsert Payment_Link_Metadata__c.Fields.Unique_Key__c;
        }

        if (!rowsToDelete.isEmpty()) {
            delete rowsToDelete;
        }
    }

    private static MetadataBuildResult buildMetadata(
        Payment_Link__c paymentLink,
        String workspaceKey,
        Map<String, Object> providedValues,
        Boolean enforceRequired
    ) {
        String resolvedWorkspace = resolveWorkspaceKey(workspaceKey);
        List<FieldDefinition> definitions = loadDefinitions(resolvedWorkspace);

        Map<String, Object> valuesByKey = new Map<String, Object>();
        if (providedValues != null) {
            for (String key : providedValues.keySet()) {
                valuesByKey.put(normalizeKey(key), providedValues.get(key));
            }
        }

        Map<String, Object> defaultValues = buildDefaultValues(paymentLink);
        for (String key : defaultValues.keySet()) {
            String normalizedKey = normalizeKey(key);
            if (!valuesByKey.containsKey(normalizedKey)) {
                valuesByKey.put(normalizedKey, defaultValues.get(key));
            }
        }

        Set<String> allowedKeys = new Set<String>();
        for (FieldDefinition definition : definitions) {
            allowedKeys.add(normalizeKey(definition.apiName));
        }

        List<String> unknownFields = new List<String>();
        if (providedValues != null) {
            for (String key : providedValues.keySet()) {
                String normalizedKey = normalizeKey(key);
                Object value = providedValues.get(key);
                if (allowedKeys.contains(normalizedKey) || isBlankValue(value)) {
                    continue;
                }
                unknownFields.add(key);
            }
        }

        if (!unknownFields.isEmpty()) {
            unknownFields.sort();
            throw new AuraHandledException(
                'Hay metadatos no configurados para el workspace "' +
                resolvedWorkspace +
                '": ' +
                String.join(unknownFields, ', ') +
                '.'
            );
        }

        MetadataBuildResult result = new MetadataBuildResult();
        Map<String, Object> normalizedJsonMap = new Map<String, Object>();
        List<String> requiredMissing = new List<String>();

        for (FieldDefinition definition : definitions) {
            Object rawValue = valuesByKey.get(normalizeKey(definition.apiName));
            MetadataEntry entry = normalizeEntry(definition, rawValue);

            if (entry.isEmpty) {
                if (enforceRequired && definition.required) {
                    requiredMissing.add(definition.label);
                }
                continue;
            }

            result.entries.add(entry);
            normalizedJsonMap.put(definition.apiName, entry.jsonValue);
        }

        if (!requiredMissing.isEmpty()) {
            requiredMissing.sort();
            throw new AuraHandledException(
                'Completa los metadatos obligatorios antes de generar la liga: ' + String.join(requiredMissing, ', ') + '.'
            );
        }

        result.metadataXml = buildMetadataXml(result.entries);
        result.searchIndex = buildSearchIndex(result.entries);
        result.normalizedJson = normalizedJsonMap.isEmpty()
            ? null
            : PolUtil.trimToMax(JSON.serialize(normalizedJsonMap), MAX_LONG_TEXT_LENGTH);

        return result;
    }

    private static MetadataEntry normalizeEntry(FieldDefinition definition, Object rawValue) {
        MetadataEntry entry = new MetadataEntry();
        entry.apiName = definition.apiName;
        entry.label = definition.label;
        entry.dataType = definition.dataType;
        entry.xmlTag = definition.xmlTag;
        entry.isEmpty = true;

        if (isBlankValue(rawValue)) {
            return entry;
        }

        if (definition.dataType == DATA_TYPE_NUMBER) {
            Decimal numberValue;
            try {
                numberValue = Decimal.valueOf(String.valueOf(rawValue).trim());
            } catch (Exception e) {
                throw new AuraHandledException('El metadato "' + definition.label + '" debe ser numero.');
            }

            Decimal cleanNumber = numberValue.stripTrailingZeros();
            entry.numberValue = cleanNumber;
            entry.stringValue = String.valueOf(cleanNumber);
            entry.jsonValue = cleanNumber;
            entry.isEmpty = false;
            return entry;
        }

        if (definition.dataType == DATA_TYPE_DATE) {
            Date parsedDate = parseDateValue(rawValue, definition.label);
            entry.dateValue = parsedDate;
            entry.stringValue = String.valueOf(parsedDate);
            entry.jsonValue = parsedDate;
            entry.isEmpty = false;
            return entry;
        }

        if (definition.dataType == DATA_TYPE_BOOLEAN) {
            Boolean parsedBoolean = parseBooleanValue(rawValue, definition.label);
            entry.booleanValue = parsedBoolean;
            entry.stringValue = parsedBoolean ? 'true' : 'false';
            entry.jsonValue = parsedBoolean;
            entry.isEmpty = false;
            return entry;
        }

        String textValue = String.valueOf(rawValue).trim();
        if (String.isBlank(textValue)) {
            return entry;
        }

        entry.stringValue = textValue;
        entry.jsonValue = textValue;
        entry.isEmpty = false;
        return entry;
    }

    private static Date parseDateValue(Object rawValue, String label) {
        if (rawValue instanceof Date) {
            return (Date) rawValue;
        }

        if (rawValue instanceof Datetime) {
            return ((Datetime) rawValue).date();
        }

        String value = String.valueOf(rawValue).trim();
        if (String.isBlank(value)) {
            return null;
        }

        try {
            return Date.valueOf(value);
        } catch (Exception ignored) {
        }

        if (Pattern.compile('^\\d{2}/\\d{2}/\\d{4}$').matcher(value).matches()) {
            List<String> parts = value.split('/');
            Integer day = Integer.valueOf(parts[0]);
            Integer month = Integer.valueOf(parts[1]);
            Integer year = Integer.valueOf(parts[2]);
            try {
                return Date.newInstance(year, month, day);
            } catch (Exception ignored) {
            }
        }

        throw new AuraHandledException(
            'El metadato "' + label + '" debe ser fecha valida (AAAA-MM-DD o DD/MM/AAAA).'
        );
    }

    private static Boolean parseBooleanValue(Object rawValue, String label) {
        if (rawValue instanceof Boolean) {
            return (Boolean) rawValue;
        }

        String value = String.valueOf(rawValue).trim().toLowerCase();
        if (
            value == 'true' ||
            value == '1' ||
            value == 'yes' ||
            value == 'si' ||
            value == 'y'
        ) {
            return true;
        }

        if (
            value == 'false' ||
            value == '0' ||
            value == 'no' ||
            value == 'n'
        ) {
            return false;
        }

        throw new AuraHandledException('El metadato "' + label + '" debe ser booleano (true/false).');
    }

    private static String buildMetadataXml(List<MetadataEntry> entries) {
        if (entries == null || entries.isEmpty()) {
            return '';
        }

        List<String> xmlParts = new List<String>();
        for (MetadataEntry entry : entries) {
            xmlParts.add('<' + entry.xmlTag + '>' + PolUtil.escapeXml(entry.stringValue) + '</' + entry.xmlTag + '>');
        }

        return '<metadata>' + String.join(xmlParts, '') + '</metadata>';
    }

    private static String buildSearchIndex(List<MetadataEntry> entries) {
        if (entries == null || entries.isEmpty()) {
            return null;
        }

        List<String> chunks = new List<String>();
        for (MetadataEntry entry : entries) {
            chunks.add(entry.apiName + '=' + entry.stringValue);
        }

        return PolUtil.trimToMax(String.join(chunks, ' | '), MAX_LONG_TEXT_LENGTH);
    }

    private static Map<String, Object> parseMetadataJson(String metadataJson) {
        Map<String, Object> values = new Map<String, Object>();
        if (String.isBlank(metadataJson)) {
            return values;
        }

        Object parsed;
        try {
            parsed = JSON.deserializeUntyped(metadataJson);
        } catch (Exception e) {
            throw new AuraHandledException('El formato JSON de metadatos es invalido: ' + e.getMessage());
        }

        try {
            values = (Map<String, Object>) parsed;
        } catch (Exception e) {
            throw new AuraHandledException('El JSON de metadatos debe ser un objeto clave/valor.');
        }

        return values;
    }

    private static Map<String, Object> buildDefaultValues(Payment_Link__c paymentLink) {
        Map<String, Object> defaults = new Map<String, Object>();
        if (paymentLink == null) {
            return defaults;
        }

        defaults.put('reference', paymentLink.Reference__c);
        defaults.put('referencia', paymentLink.Reference__c);
        defaults.put('amount', paymentLink.Amount__c);
        defaults.put('monto', paymentLink.Amount__c);
        defaults.put('customer', paymentLink.Customer_Name__c);
        defaults.put('cliente', paymentLink.Customer_Name__c);
        defaults.put('concept', paymentLink.Concept__c);
        defaults.put('concepto', paymentLink.Concept__c);
        defaults.put('canal', 'W');

        return defaults;
    }

    private static List<FieldDefinition> loadDefinitions(String workspaceKey) {
        List<FieldDefinition> rawDefinitions = new List<FieldDefinition>();

        if (Test.isRunningTest() && definitionOverrides != null) {
            for (FieldDefinition overrideDefinition : definitionOverrides) {
                rawDefinitions.add(cloneDefinition(overrideDefinition));
            }
        } else {
            List<Payment_Link_Metadata_Field__mdt> metadataDefinitions = [
                SELECT
                    DeveloperName,
                    MasterLabel,
                    Workspace__c,
                    Field_API_Name__c,
                    Field_Label__c,
                    Data_Type__c,
                    Required__c,
                    Active__c,
                    Xml_Tag__c,
                    Sort_Order__c
                FROM Payment_Link_Metadata_Field__mdt
                WHERE Active__c = true
                ORDER BY Sort_Order__c ASC, MasterLabel ASC
            ];

            for (Payment_Link_Metadata_Field__mdt metadataDefinition : metadataDefinitions) {
                FieldDefinition definition = new FieldDefinition();
                definition.apiName = String.isBlank(metadataDefinition.Field_API_Name__c)
                    ? metadataDefinition.DeveloperName
                    : metadataDefinition.Field_API_Name__c;
                definition.label = String.isBlank(metadataDefinition.Field_Label__c)
                    ? metadataDefinition.MasterLabel
                    : metadataDefinition.Field_Label__c;
                definition.dataType = metadataDefinition.Data_Type__c;
                definition.required = metadataDefinition.Required__c;
                definition.active = metadataDefinition.Active__c;
                definition.xmlTag = metadataDefinition.Xml_Tag__c;
                definition.workspace = metadataDefinition.Workspace__c;
                definition.sortOrder = metadataDefinition.Sort_Order__c == null
                    ? null
                    : metadataDefinition.Sort_Order__c.intValue();
                rawDefinitions.add(definition);
            }
        }

        String resolvedWorkspace = resolveWorkspaceKey(workspaceKey);

        List<FieldDefinition> workspaceDefinitions = new List<FieldDefinition>();
        List<FieldDefinition> globalDefinitions = new List<FieldDefinition>();

        Map<String, String> duplicatesByWorkspace = new Map<String, String>();

        for (FieldDefinition rawDefinition : rawDefinitions) {
            FieldDefinition normalized = normalizeDefinition(rawDefinition);
            if (!normalized.active) {
                continue;
            }

            String duplicateKey = normalizeKey(normalized.workspace) + '|' + normalizeKey(normalized.apiName);
            if (duplicatesByWorkspace.containsKey(duplicateKey)) {
                throw new AuraHandledException(
                    'La configuracion de metadatos tiene campos duplicados: ' +
                    normalized.apiName +
                    ' en workspace ' +
                    (String.isBlank(normalized.workspace) ? '(global)' : normalized.workspace) +
                    '.'
                );
            }
            duplicatesByWorkspace.put(duplicateKey, normalized.apiName);

            if (String.isBlank(normalized.workspace)) {
                globalDefinitions.add(normalized);
            }

            if (equalsIgnoreCase(normalized.workspace, resolvedWorkspace)) {
                workspaceDefinitions.add(normalized);
            }
        }

        List<FieldDefinition> selected = workspaceDefinitions.isEmpty() ? globalDefinitions : workspaceDefinitions;
        selected.sort();
        return selected;
    }

    private static FieldDefinition normalizeDefinition(FieldDefinition definition) {
        if (definition == null) {
            throw new AuraHandledException('Se encontro una configuracion de metadato vacia.');
        }

        FieldDefinition normalized = cloneDefinition(definition);

        normalized.apiName = normalizeApiName(normalized.apiName);
        normalized.label = String.isBlank(normalized.label) ? normalized.apiName : normalized.label.trim();
        normalized.workspace = String.isBlank(normalized.workspace) ? null : normalized.workspace.trim();
        normalized.dataType = normalizeDataType(normalized.dataType, normalized.label);
        normalized.required = normalized.required == null ? false : normalized.required;
        normalized.active = normalized.active == null ? true : normalized.active;
        normalized.xmlTag = sanitizeXmlTag(String.isBlank(normalized.xmlTag) ? normalized.apiName : normalized.xmlTag);

        return normalized;
    }

    private static FieldDefinition cloneDefinition(FieldDefinition definition) {
        return new FieldDefinition(
            definition.apiName,
            definition.label,
            definition.dataType,
            definition.required,
            definition.active,
            definition.xmlTag,
            definition.sortOrder,
            definition.workspace
        );
    }

    private static String resolveWorkspaceKey(String workspaceKey) {
        return String.isBlank(workspaceKey) ? 'DEFAULT' : workspaceKey.trim();
    }

    private static String normalizeDataType(String rawType, String label) {
        if (String.isBlank(rawType)) {
            return DATA_TYPE_TEXT;
        }

        String token = rawType.trim().toLowerCase();
        if (token == 'text' || token == 'texto' || token == 'string') {
            return DATA_TYPE_TEXT;
        }
        if (token == 'number' || token == 'numero' || token == 'numeric') {
            return DATA_TYPE_NUMBER;
        }
        if (token == 'date' || token == 'fecha') {
            return DATA_TYPE_DATE;
        }
        if (token == 'boolean' || token == 'bool' || token == 'checkbox') {
            return DATA_TYPE_BOOLEAN;
        }

        throw new AuraHandledException(
            'El campo "' + label + '" tiene un tipo de dato invalido en configuracion. Usa Text, Number, Date o Boolean.'
        );
    }

    private static String normalizeApiName(String apiName) {
        if (String.isBlank(apiName)) {
            throw new AuraHandledException('Cada metadato configurado debe tener Field_API_Name__c.');
        }

        String normalized = apiName.trim().replace(' ', '_');
        normalized = normalized.replace('-', '_');
        if (!Pattern.compile('^[A-Za-z][A-Za-z0-9_]*$').matcher(normalized).matches()) {
            throw new AuraHandledException(
                'Field_API_Name__c invalido: "' +
                apiName +
                '". Usa solo letras, numeros y guion bajo, iniciando con letra.'
            );
        }

        return normalized;
    }

    private static String sanitizeXmlTag(String xmlTag) {
        String safeTag = String.isBlank(xmlTag) ? 'metadata_value' : xmlTag.trim();
        safeTag = safeTag.replace(' ', '_').replace('-', '_');

        List<String> chars = new List<String>();
        for (Integer i = 0; i < safeTag.length(); i++) {
            String ch = safeTag.substring(i, i + 1);
            if (Pattern.compile('^[A-Za-z0-9_]$').matcher(ch).matches()) {
                chars.add(ch);
            } else {
                chars.add('_');
            }
        }

        String sanitized = String.join(chars, '');
        if (String.isBlank(sanitized)) {
            sanitized = 'metadata_value';
        }

        String firstChar = sanitized.substring(0, 1);
        if (!Pattern.compile('^[A-Za-z_]$').matcher(firstChar).matches()) {
            sanitized = 'm_' + sanitized;
        }

        return sanitized;
    }

    private static String normalizeKey(String key) {
        return String.isBlank(key) ? '' : key.trim().toLowerCase();
    }

    private static Boolean equalsIgnoreCase(String left, String right) {
        if (String.isBlank(left) || String.isBlank(right)) {
            return false;
        }

        return normalizeKey(left) == normalizeKey(right);
    }

    private static Boolean isBlankValue(Object value) {
        if (value == null) {
            return true;
        }

        if (value instanceof String) {
            return String.isBlank((String) value);
        }

        return false;
    }
}
