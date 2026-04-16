public with sharing class PaymentLinkService {
    private static final String DEFAULT_CONFIG_NAME = 'ConfiguracionPrueba';
    private static final Integer DEFAULT_TIMEOUT_MS = 15000;
    private static final Integer MIN_TIMEOUT_MS = 1000;
    private static final Integer MAX_TIMEOUT_MS = 120000;
    private static final Integer DEFAULT_MAX_RETRIES = 0;
    private static final Integer MAX_ALLOWED_RETRIES = 5;

    @TestVisible
    private static Integer timeoutOverrideMs;

    @TestVisible
    private static Integer maxRetriesOverride;

    @TestVisible
    private static String configNameOverride;

    private class ConfigResolution {
        public String configName;
        public PagosOnline_Config__mdt configRecord;
    }

    @AuraEnabled
    public static Payment_Link__c generateLink(Id paymentLinkId) {
        Payment_Link__c p = [
            SELECT
                Id,
                Amount__c,
                Currency__c,
                Reference__c,
                Concept__c,
                Customer_Name__c,
                Expiration_Date__c,
                Workspace__c,
                Metadata_JSON__c,
                Metadata_Index__c,
                Status__c,
                Attempt_Count__c,
                Payment_URL__c,
                Provider_Transaction_ID__c,
                Raw_Request__c,
                Raw_Response__c
            FROM Payment_Link__c
            WHERE Id = :paymentLinkId
            LIMIT 1
        ];

        return generateLinkFromRecord(p);
    }

    public static Payment_Link__c generateLinkFromDraft(Payment_Link__c paymentLinkDraft) {
        if (paymentLinkDraft == null) {
            throw new AuraHandledException('Payment Link es obligatorio para generar la liga.');
        }

        return generateLinkFromRecord(paymentLinkDraft);
    }

    private static Payment_Link__c generateLinkFromRecord(Payment_Link__c p) {
        if (p.Amount__c == null || p.Amount__c <= 0) {
            throw new AuraHandledException('Monto invalido (debe ser > 0).');
        }
        if (String.isBlank(p.Reference__c)) {
            throw new AuraHandledException('Referencia requerida.');
        }

        String workspaceKey = resolveWorkspaceKey(p);
        ConfigResolution resolvedConfig = resolveConfigForWorkspace(workspaceKey);
        PagosOnline_Config__mdt cfg = resolvedConfig.configRecord;
        String configName = resolvedConfig.configName;
        if (cfg == null) {
            throw new AuraHandledException('Falta PagosOnline_Config__mdt.' + configName);
        }
        if (String.isBlank(cfg.GeneratePath__c)) {
            throw new AuraHandledException('Falta GeneratePath__c en ' + configName + ' (debe ser /gen).');
        }
        if (String.isBlank(cfg.Data0__c)) {
            throw new AuraHandledException('Falta Data0__c en ' + configName + '.');
        }
        if (String.isBlank(cfg.AESKeyHex__c)) {
            throw new AuraHandledException('Falta AESKeyHex__c en ' + configName + ' (32 hex chars = 16 bytes).');
        }

        PaymentLinkMetadataService.MetadataBuildResult metadataBuildResult = PaymentLinkMetadataService.prepareForGeneration(
            p,
            workspaceKey
        );

        String requestXml = buildRequestXml(p, cfg, metadataBuildResult.metadataXml);
        String encryptedB64 = PolCrypto.encryptB64(requestXml, cfg.AESKeyHex__c);
        String wrapperXml = PolUtil.buildPgsWrapper(cfg.Data0__c, encryptedB64);

        p.Raw_Request__c = wrapperXml;

        Integer timeoutMs = resolveTimeoutMs(cfg);
        Integer maxRetries = resolveMaxRetries(cfg);
        List<String> auditLines = new List<String>();

        HttpResponse res;
        String rawRes;
        Exception lastCalloutException;
        Integer attemptsUsed = 0;

        for (Integer attempt = 0; attempt <= maxRetries; attempt++) {
            attemptsUsed++;
            try {
                HttpRequest req = new HttpRequest();
                req.setMethod('POST');
                req.setTimeout(timeoutMs);
                req.setEndpoint('callout:POL_Sandbox' + cfg.GeneratePath__c);
                req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
                req.setBody('xml=' + EncodingUtil.urlEncode(wrapperXml, 'UTF-8'));

                res = new Http().send(req);
                rawRes = res.getBody();
                auditLines.add('Intento ' + attemptsUsed + ': HTTP ' + res.getStatusCode() + ' ' + res.getStatus());

                if (!isRetryableStatus(res.getStatusCode()) || attempt == maxRetries) {
                    break;
                }
            } catch (Exception e) {
                lastCalloutException = e;
                auditLines.add('Intento ' + attemptsUsed + ': EXCEPTION ' + e.getMessage());
                if (attempt == maxRetries) {
                    break;
                }
            }
        }

        Decimal previousAttempts = p.Attempt_Count__c == null ? 0 : p.Attempt_Count__c;
        p.Attempt_Count__c = previousAttempts + attemptsUsed;

        if (res == null) {
            p.Status__c = 'Error';
            p.Raw_Response__c = PolUtil.appendAudit(
                p.Raw_Response__c,
                'No hubo respuesta del proveedor.' +
                '\n' +
                PolUtil.joinLines(auditLines) +
                (lastCalloutException == null ? '' : '\n' + lastCalloutException.getMessage())
            );
            persistPaymentLink(p, workspaceKey, metadataBuildResult);
            throw new AuraHandledException('No hubo respuesta del proveedor. Revisa Raw_Response__c.');
        }

        Integer sc = res.getStatusCode();
        if (sc != 200 || (rawRes != null && rawRes.trim().startsWith('['))) {
            p.Status__c = 'Error';
            p.Raw_Response__c = PolUtil.appendAudit(
                p.Raw_Response__c,
                PolUtil.joinLines(auditLines) + '\n' + (rawRes == null ? '' : rawRes)
            );
            persistPaymentLink(p, workspaceKey, metadataBuildResult);
            throw new AuraHandledException('Error del proveedor. Revisa Raw_Response__c.');
        }

        String b64 = PolUtil.extractTag(rawRes, 'data');
        if (String.isBlank(b64)) {
            b64 = rawRes == null ? null : rawRes.trim();
        }

        String decrypted;
        try {
            decrypted = PolCrypto.decryptB64(b64, cfg.AESKeyHex__c);
        } catch (Exception e) {
            p.Status__c = 'Error';
            p.Raw_Response__c = PolUtil.appendAudit(
                p.Raw_Response__c,
                PolUtil.joinLines(auditLines) +
                '\nRAW:\n' +
                (rawRes == null ? '' : rawRes) +
                '\nERROR:\n' +
                e.getMessage()
            );
            persistPaymentLink(p, workspaceKey, metadataBuildResult);
            throw new AuraHandledException('No pude descifrar la respuesta. Revisa Raw_Response__c.');
        }

        String url = PolUtil.extractFirstUrl(decrypted);
        if (String.isBlank(url)) {
            p.Status__c = 'Error';
            p.Raw_Response__c = PolUtil.appendAudit(
                p.Raw_Response__c,
                PolUtil.joinLines(auditLines) + '\n' + decrypted
            );
            persistPaymentLink(p, workspaceKey, metadataBuildResult);
            throw new AuraHandledException('No encontre URL en la respuesta descifrada. Revisa Raw_Response__c.');
        }

        String providerTransactionId = extractProviderTransactionId(decrypted);
        p.Payment_URL__c = url;
        if (!String.isBlank(providerTransactionId)) {
            p.Provider_Transaction_ID__c = providerTransactionId;
        }
        p.Status__c = 'Pending';
        p.Raw_Response__c = PolUtil.appendAudit(
            p.Raw_Response__c,
            PolUtil.joinLines(auditLines) + '\n' + decrypted
        );
        persistPaymentLink(p, workspaceKey, metadataBuildResult);

        return p;
    }

    private static ConfigResolution resolveConfigForWorkspace(String workspaceKey) {
        String requestedConfigName = getConfigName(workspaceKey);
        PagosOnline_Config__mdt requestedConfig = PagosOnline_Config__mdt.getInstance(requestedConfigName);
        if (requestedConfig != null) {
            ConfigResolution directResolution = new ConfigResolution();
            directResolution.configName = requestedConfigName;
            directResolution.configRecord = requestedConfig;
            return directResolution;
        }

        if (requestedConfigName != DEFAULT_CONFIG_NAME) {
            PagosOnline_Config__mdt fallbackConfig = PagosOnline_Config__mdt.getInstance(DEFAULT_CONFIG_NAME);
            if (fallbackConfig != null) {
                ConfigResolution fallbackResolution = new ConfigResolution();
                fallbackResolution.configName = DEFAULT_CONFIG_NAME;
                fallbackResolution.configRecord = fallbackConfig;
                return fallbackResolution;
            }
        }

        ConfigResolution missingResolution = new ConfigResolution();
        missingResolution.configName = requestedConfigName;
        missingResolution.configRecord = null;
        return missingResolution;
    }

    private static String getConfigName(String workspaceKey) {
        if (Test.isRunningTest() && !String.isBlank(configNameOverride)) {
            return configNameOverride;
        }
        if (!String.isBlank(workspaceKey)) {
            return workspaceKey.trim();
        }
        return DEFAULT_CONFIG_NAME;
    }

    private static Integer resolveTimeoutMs(PagosOnline_Config__mdt cfg) {
        if (Test.isRunningTest() && timeoutOverrideMs != null) {
            return timeoutOverrideMs;
        }

        Integer resolved = DEFAULT_TIMEOUT_MS;
        if (cfg.TimeoutMs__c != null) {
            resolved = cfg.TimeoutMs__c.intValue();
        }

        if (resolved < MIN_TIMEOUT_MS) {
            return MIN_TIMEOUT_MS;
        }
        if (resolved > MAX_TIMEOUT_MS) {
            return MAX_TIMEOUT_MS;
        }
        return resolved;
    }

    private static Integer resolveMaxRetries(PagosOnline_Config__mdt cfg) {
        if (Test.isRunningTest() && maxRetriesOverride != null) {
            return maxRetriesOverride;
        }

        Integer resolved = DEFAULT_MAX_RETRIES;
        if (cfg.MaxRetries__c != null) {
            resolved = cfg.MaxRetries__c.intValue();
        }

        if (resolved < 0) {
            return 0;
        }
        if (resolved > MAX_ALLOWED_RETRIES) {
            return MAX_ALLOWED_RETRIES;
        }
        return resolved;
    }

    private static Boolean isRetryableStatus(Integer statusCode) {
        if (statusCode == null) {
            return true;
        }
        return statusCode == 408 || statusCode == 429 || statusCode >= 500;
    }

    private static String extractProviderTransactionId(String payload) {
        List<String> tags = new List<String>{
            'id_transaccion',
            'idTransaccion',
            'transaction_id',
            'transactionId',
            'id_operacion',
            'idOperacion',
            'auth'
        };

        for (String tag : tags) {
            String value = PolUtil.extractTag(payload, tag);
            if (!String.isBlank(value)) {
                return value;
            }
        }

        return null;
    }

    private static String resolveWorkspaceKey(Payment_Link__c paymentLink) {
        if (!String.isBlank(paymentLink.Workspace__c)) {
            return paymentLink.Workspace__c.trim();
        }
        return DEFAULT_CONFIG_NAME;
    }

    private static void persistPaymentLink(
        Payment_Link__c paymentLink,
        String workspaceKey,
        PaymentLinkMetadataService.MetadataBuildResult metadataBuildResult
    ) {
        try {
            if (paymentLink.Id == null) {
                insert paymentLink;
            } else {
                update paymentLink;
            }
            PaymentLinkMetadataService.syncMetadataRows(paymentLink.Id, workspaceKey, metadataBuildResult);
        } catch (DmlException e) {
            if (Test.isRunningTest()) {
                throw e;
            }
            throw new AuraHandledException('No se pudo guardar la liga con metadatos: ' + e.getDmlMessage(0));
        }
    }

    private static String buildRequestXml(
        Payment_Link__c p,
        PagosOnline_Config__mdt cfg,
        String metadataXml
    ) {
        String concept = PolUtil.escapeXml(p.Concept__c);
        String customer = PolUtil.escapeXml(p.Customer_Name__c);

        String vigencia = '';
        if (p.Expiration_Date__c != null) {
            vigencia = p.Expiration_Date__c.format('dd/MM/yyyy');
        }

        Decimal amount = p.Amount__c.setScale(2);
        String amountText = String.valueOf(amount);
        String currencyCode = resolveCurrencyCode(p.Currency__c);

        return
            '<?xml version="1.0" encoding="UTF-8"?>' +
            '<P>' +
            '<business>' +
            '<id_company>' +
            PolUtil.escapeXml(cfg.CompanyId__c) +
            '</id_company>' +
            '<id_branch>' +
            PolUtil.escapeXml(cfg.BranchId__c) +
            '</id_branch>' +
            '<user>' +
            PolUtil.escapeXml(cfg.User__c) +
            '</user>' +
            '<pwd>' +
            PolUtil.escapeXml(cfg.Password__c) +
            '</pwd>' +
            '</business>' +
            '<url>' +
            '<reference>' +
            PolUtil.escapeXml(p.Reference__c) +
            '</reference>' +
            '<amount>' +
            amountText +
            '</amount>' +
            '<moneda>' +
            PolUtil.escapeXml(currencyCode) +
            '</moneda>' +
            '<canal>W</canal>' +
            (String.isBlank(concept) ? '' : '<concepto>' + concept + '</concepto>') +
            (String.isBlank(vigencia) ? '' : '<fh_vigencia>' + vigencia + '</fh_vigencia>') +
            (String.isBlank(customer) ? '' : '<mail_cliente>' + customer + '</mail_cliente>') +
            (String.isBlank(metadataXml) ? '' : metadataXml) +
            '</url>' +
            '</P>';
    }

    private static String resolveCurrencyCode(String rawCurrency) {
        if (String.isBlank(rawCurrency)) {
            return 'MXN';
        }

        String normalized = rawCurrency.trim().toUpperCase();
        if (!Pattern.compile('^[A-Z]{3}$').matcher(normalized).matches()) {
            return 'MXN';
        }

        return normalized;
    }
}
