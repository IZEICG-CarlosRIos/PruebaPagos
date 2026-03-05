public with sharing class PaymentLinkService {
    @AuraEnabled
    public static Payment_Link__c generateLink(Id paymentLinkId) {
        Payment_Link__c p = [
            SELECT Id, Amount__c, Reference__c, Concept__c, Customer_Name__c,
                   Expiration_Date__c, Status__c, Attempt_Count__c,
                   Payment_URL__c, Provider_Transaction_ID__c,
                   Raw_Request__c, Raw_Response__c
            FROM Payment_Link__c
            WHERE Id = :paymentLinkId
            LIMIT 1
        ];

        if (p.Amount__c == null || p.Amount__c <= 0) {
            throw new AuraHandledException('Monto inválido (debe ser > 0).');
        }
        if (String.isBlank(p.Reference__c)) {
            throw new AuraHandledException('Referencia requerida.');
        }

        // Config (Manage Records -> ConfiguracionPrueba)
        PagosOnline_Config__mdt cfg = PagosOnline_Config__mdt.getInstance('ConfiguracionPrueba');
        System.debug(cfg);

        if (cfg == null) throw new AuraHandledException('Falta PagosOnline_Config__mdt.ConfiguracionPrueba');
        if (String.isBlank(cfg.GeneratePath__c)) throw new AuraHandledException('Falta GeneratePath__c en ConfiguracionPrueba (debe ser /gen).');
        if (String.isBlank(cfg.Data0__c)) throw new AuraHandledException('Falta Data0__c en ConfiguracionPrueba (para sandbox debe ser SNDBX123).');
        if (String.isBlank(cfg.AesKeyHex__c)) throw new AuraHandledException('Falta AesKeyHex__c en ConfiguracionPrueba (32 hex chars = 16 bytes).');

        String requestXml = buildRequestXml(p, cfg);

        String encryptedB64 = PolCrypto.encryptB64(requestXml, cfg.AesKeyHex__c);

        String wrapperXml = PolUtil.buildPgsWrapper(cfg.Data0__c, encryptedB64);

        p.Raw_Request__c = wrapperXml;
        p.Attempt_Count__c = (p.Attempt_Count__c == null) ? 1 : p.Attempt_Count__c + 1;

        HttpRequest req = new HttpRequest();
        req.setMethod('POST');
        req.setTimeout(15000);

        req.setEndpoint('callout:POL_Sandbox' + cfg.GeneratePath__c);

        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        req.setBody('xml=' + EncodingUtil.urlEncode(wrapperXml, 'UTF-8'));

        HttpResponse res = new Http().send(req);
        Integer sc = res.getStatusCode();
        String rawRes = res.getBody();

        System.debug('HTTP ' + sc + ' ' + res.getStatus());
        System.debug(rawRes);

        if (sc != 200 || (rawRes != null && rawRes.trim().startsWith('['))) {
            p.Status__c = 'Error';
            p.Raw_Response__c = 'HTTP ' + sc + ' ' + res.getStatus() + '\n' + (rawRes == null ? '' : rawRes);
            update p;
            throw new AuraHandledException('Error del proveedor. Revisa Raw_Response__c.');
        }

        String b64 = PolUtil.extractTag(rawRes, 'data');
        if (String.isBlank(b64)) b64 = rawRes != null ? rawRes.trim() : null;

        String decrypted;
        try {
            decrypted = PolCrypto.decryptB64(b64, cfg.AesKeyHex__c);
        } catch (Exception e) {
            p.Status__c = 'Error';
            p.Raw_Response__c = 'RAW:\n' + (rawRes == null ? '' : rawRes) + '\n\nERROR:\n' + e.getMessage();
            update p;
            throw new AuraHandledException('No pude descifrar la respuesta. Revisa Raw_Response__c.');
        }

        String url = PolUtil.extractFirstUrl(decrypted);
        if (String.isBlank(url)) {
            p.Status__c = 'Error';
            p.Raw_Response__c = decrypted;
            update p;
            throw new AuraHandledException('No encontré URL en la respuesta descifrada. Revisa Raw_Response__c.');
        }

        p.Payment_URL__c = url;
        p.Status__c = 'Pending';
        p.Raw_Response__c = decrypted;
        update p;

        return p;
    }

    private static String buildRequestXml(Payment_Link__c p, PagosOnline_Config__mdt cfg) {
        String concept = PolUtil.escapeXml(p.Concept__c);
        String customer = PolUtil.escapeXml(p.Customer_Name__c);

        String vigencia = '';
        if (p.Expiration_Date__c != null) {
            vigencia = p.Expiration_Date__c.format('dd/MM/yyyy');
        }

        return '<?xml version="1.0" encoding="UTF-8"?>' +
            '<P>' +
              '<business>' +
                '<id_company>' + PolUtil.escapeXml(cfg.CompanyId__c) + '</id_company>' +
                '<id_branch>' + PolUtil.escapeXml(cfg.BranchId__c) + '</id_branch>' +
                '<user>' + PolUtil.escapeXml(cfg.User__c) + '</user>' +
                '<pwd>' + PolUtil.escapeXml(cfg.Password__c) + '</pwd>' +
              '</business>' +
              '<url>' +
                '<reference>' + PolUtil.escapeXml(p.Reference__c) + '</reference>' +
                '<amount>' + String.valueOf(p.Amount__c) + '</amount>' +
                '<moneda>MXN</moneda>' +
                '<canal>W</canal>' +
                (String.isBlank(concept) ? '' : '<concepto>' + concept + '</concepto>') +
                (String.isBlank(vigencia) ? '' : '<fh_vigencia>' + vigencia + '</fh_vigencia>') +
                (String.isBlank(customer) ? '' : '<mail_cliente>' + customer + '</mail_cliente>') +
              '</url>' +
            '</P>';
    }
}