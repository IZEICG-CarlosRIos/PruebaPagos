# Integracion PagosOnline (Salesforce)

Este proyecto implementa la generacion de ligas de pago de PagosOnline y el procesamiento de callback de confirmacion.

## Componentes

- `Payment_Link__c`: registro de transacciones y auditoria.
- `Payment_Link_Metadata__c`: almacenamiento estructurado de metadatos por liga para filtros/reportes.
- `PaymentLinkService`: genera XML, cifra (AES), envia callout y guarda URL.
- `PaymentLinkMetadataService`: valida metadatos configurados, normaliza tipos y sincroniza detalle por liga.
- `PaymentLinkFlowActions`: accion invocable para usar en Flow.
- `PaymentLinkCallbackApi`: endpoint REST para notificaciones del proveedor.
- `PagosOnline_Config__mdt`: parametros de integracion.
- `Payment_Link_Metadata_Field__mdt`: definicion configurable de metadatos por workspace.

## Flujo funcional

1. Usuario captura `Amount__c`, `Reference__c`, `Concept__c`, `Customer_Name__c` y metadatos en `Metadata_JSON__c`.
2. Se invoca `PaymentLinkService.generateLink` (directo o por Flow Action).
3. El servicio:
   - valida datos obligatorios,
   - valida metadatos configurados por workspace y campos requeridos,
   - normaliza metadatos (texto, numero, fecha, booleano),
   - arma XML,
   - cifra payload con `PolCrypto` (AES128 + managed IV),
   - envia `POST` a `callout:POL_Sandbox + GeneratePath__c`,
   - descifra respuesta,
   - sincroniza metadatos tipados en `Payment_Link_Metadata__c`,
   - guarda `Payment_URL__c`, `Status__c = Pending`, intentos y logs.
4. Cliente paga en la URL generada.
5. PagosOnline llama a `/services/apexrest/pagosonline/callback`.
6. `PaymentLinkCallbackApi` actualiza el estado a `Approved/Rejected/Pending/Expired`.

## Configuracion requerida

### 1) Named Credential

Crear `Named Credential` con este nombre exacto:

- `POL_Sandbox`

URL base sugerida para sandbox:

- `https://sandboxpol.mit.com.mx`

### 2) Custom Metadata

Registro: `PagosOnline_Config__mdt.ConfiguracionPrueba`

Campos minimos:

- `CompanyId__c`
- `BranchId__c`
- `User__c`
- `Password__c`
- `Data0__c`
- `AESKeyHex__c`
- `GeneratePath__c` (ej. `/gen`)
- `TimeoutMs__c` (ej. `15000`)
- `MaxRetries__c` (ej. `2`)

### 3) Definicion de metadatos por workspace

Tipo: `Payment_Link_Metadata_Field__mdt`

Campos:

- `Workspace__c`: llave de tenant/workspace (ej. `ConfiguracionPrueba`).
- `Field_API_Name__c`: nombre tecnico usado en JSON.
- `Field_Label__c`: etiqueta para UI y mensajes de error.
- `Data_Type__c`: `Text`, `Number`, `Date`, `Boolean`.
- `Required__c`: define si se exige antes de generar la liga.
- `Active__c`: habilita/deshabilita el metadato.
- `Xml_Tag__c`: tag a incluir en el XML al proveedor.
- `Sort_Order__c`: orden en UI y serializacion.

Ejemplos incluidos:

- `Payment_Link_Metadata_Field.Producto_ConfiguracionPrueba`
- `Payment_Link_Metadata_Field.Canal_ConfiguracionPrueba`

### 4) Campos nuevos en Payment Link

- `Workspace__c`: tenant/workspace de la liga.
- `Metadata_JSON__c`: JSON con los metadatos capturados.
- `Metadata_Index__c`: texto indexado para busquedas rapidas.

## Callback

Endpoint REST Apex:

- `POST /services/apexrest/pagosonline/callback`

Payload soportado:

- XML plano con tags como `reference`, `status`.
- Wrapper con `<data>` cifrado en base64.
- Formato `application/x-www-form-urlencoded` con llaves `xml` o `data`.

Reglas de estado:

- `APPROVED`, `OK`, `00`, `PAGADO` -> `Approved`
- `REJECTED`, `FAILED`, `05`, `51` -> `Rejected`
- `EXPIRED`, `VENCIDO` -> `Expired`
- Cualquier otro -> `Pending`

## Reglas de negocio cubiertas

- No permite monto `<= 0`.
- Referencia unica (`Reference__c` marcado como `External ID + Unique`).
- Se registra cada intento (`Attempt_Count__c`).
- Se guardan request/response crudos para auditoria (`Raw_Request__c`, `Raw_Response__c`).
- Los metadatos configurados se agregan automaticamente al XML de generacion.
- Los campos de metadatos requeridos se validan antes del callout.
- Metadatos persistidos en formato estructurado (`Payment_Link_Metadata__c`) para filtros/reportes.
- Configuracion multi-tenant por `Workspace__c`.

## Pruebas

Clases de prueba incluidas:

- `PaymentLinkServiceTest`
- `PaymentLinkCallbackApiTest`
- `PaymentLinkMetadataServiceTest`

Ejemplo para correr pruebas en org destino:

```bash
sf apex run test --tests PaymentLinkServiceTest,PaymentLinkCallbackApiTest,PaymentLinkMetadataServiceTest --result-format human --wait 10
```

## Notas operativas

- Salesforce usa TLS 1.2+ en callouts HTTPS.
- El endpoint callback debe estar expuesto/publicado para que el proveedor pueda notificar.
- Ajusta `TimeoutMs__c` y `MaxRetries__c` segun SLA del proveedor.
