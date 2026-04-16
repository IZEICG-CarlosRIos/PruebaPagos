import { api, LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import getMappedRecordContext from '@salesforce/apex/GetNetMappedPaymentLinkFacade.getMappedRecordContext';
import generateFromMappedRecordDirect from '@salesforce/apex/GetNetMappedPaymentLinkFacade.generateFromMappedRecordDirect';
import getWorkspaceOptions from '@salesforce/apex/GetNetPaymentUiFacade.getWorkspaceOptions';
import getQuickPaymentFieldDefinitions from '@salesforce/apex/GetNetPaymentUiFacade.getQuickPaymentFieldDefinitions';

const CURRENCY_OPTIONS = [
    { label: 'MXN', value: 'MXN' },
    { label: 'USD', value: 'USD' }
];

const BOOLEAN_OPTIONS = [
    { label: 'Select', value: '' },
    { label: 'True', value: 'true' },
    { label: 'False', value: 'false' }
];

export default class GetnetGeneratePaymentLinkAction extends LightningElement {
    _recordId;
    _objectApiName;
    hasInitializedContext = false;
    isInitializingContext = false;

    isBusy = false;
    statusMessage = 'Detectando mapping activo...';

    workspaceOptions = [];
    metadataFields = [];
    contextData = null;

    result = null;
    existingLinkResult = null;

    form = {
        reference: '',
        amount: null,
        currency: 'MXN',
        concept: '',
        customerName: '',
        workspace: ''
    };

    currencyOptions = CURRENCY_OPTIONS;
    quickPaymentBooleanOptions = BOOLEAN_OPTIONS;

    @api
    get recordId() {
        return this._recordId;
    }

    set recordId(value) {
        this._recordId = value;
        // Temporal debug log requested for record action context.
        // eslint-disable-next-line no-console
        console.log('recordId', this._recordId);
        this.tryInitializeContext();
    }

    @api
    get objectApiName() {
        return this._objectApiName;
    }

    set objectApiName(value) {
        this._objectApiName = value;
        // Temporal debug log requested for record action context.
        // eslint-disable-next-line no-console
        console.log('objectApiName', this._objectApiName);
        this.tryInitializeContext();
    }

    connectedCallback() {
        this.tryInitializeContext();
    }

    tryInitializeContext() {
        if (this.hasInitializedContext || this.isInitializingContext) {
            return;
        }

        // Temporal debug logs requested to confirm context values.
        // eslint-disable-next-line no-console
        console.log('recordId', this.recordId);
        // eslint-disable-next-line no-console
        console.log('objectApiName', this.objectApiName);

        if (!this.recordId || !this.objectApiName) {
            this.statusMessage = 'Esperando contexto del registro...';
            return;
        }

        this.isInitializingContext = true;
        this.hasInitializedContext = true;
        this.initialize();
    }

    async initialize() {
        this.isBusy = true;
        this.statusMessage = 'Detectando mapping activo...';

        try {
            const context = await getMappedRecordContext({
                recordId: this.recordId,
                objectApiName: this.objectApiName,
                workspace: null
            });
            this.contextData = context;
            this.applyMappedContext(context);

            await this.loadWorkspaceOptions(false);

            if (!this.form.workspace) {
                this.form = {
                    ...this.form,
                    workspace: this.workspaceOptions.length > 0 ? this.workspaceOptions[0].value : ''
                };
            }

            const initialMetadataValues = this.parseMetadataJsonMap(context?.existingMetadataJson);
            await this.loadMetadataFieldDefinitions(this.form.workspace, initialMetadataValues, false);

            this.statusMessage = context?.message || 'Completa los datos para generar la liga.';
        } catch (error) {
            this.statusMessage = 'No se pudo preparar la accion de generacion.';
            this.showToast('Generate Payment Link', this.getErrorMessage(error), 'error');
        } finally {
            this.isBusy = false;
            this.isInitializingContext = false;
        }
    }

    applyMappedContext(context) {
        const mappedCurrency = String(context?.currencyCode || 'MXN').toUpperCase();

        this.form = {
            ...this.form,
            reference: context?.reference || '',
            amount: context?.amount ?? null,
            currency: mappedCurrency,
            concept: context?.concept || '',
            customerName: context?.customerName || '',
            workspace: context?.workspace || ''
        };

        if (context?.hasExistingLink) {
            this.existingLinkResult = {
                paymentLinkId: context.existingPaymentLinkId,
                paymentUrl: context.existingPaymentUrl,
                status: context.existingStatus,
                workspace: context.workspace,
                currency: context.currencyCode,
                metadataJson: context.existingMetadataJson,
                metadataIndex: context.existingMetadataIndex,
                message: 'Liga existente detectada para esta referencia.',
                wasExisting: true
            };
        } else {
            this.existingLinkResult = null;
        }
    }

    async loadWorkspaceOptions(manageState = true) {
        if (manageState) {
            this.isBusy = true;
        }

        try {
            const options = await getWorkspaceOptions({});
            this.workspaceOptions = (options || []).map((option) => ({
                label: option.label,
                value: option.value
            }));
        } catch (error) {
            this.workspaceOptions = [];
            throw error;
        } finally {
            if (manageState) {
                this.isBusy = false;
            }
        }
    }

    async loadMetadataFieldDefinitions(workspaceKey, metadataValues, manageState = true) {
        if (!workspaceKey) {
            this.metadataFields = [];
            return;
        }

        if (manageState) {
            this.isBusy = true;
        }

        try {
            const fieldDefinitions = await getQuickPaymentFieldDefinitions({ workspaceKey });
            const incomingValues = metadataValues || {};

            this.metadataFields = (fieldDefinitions || []).map((definition) => {
                const dataType = definition.dataType || 'Text';
                const rawValue = incomingValues[definition.apiName];

                return {
                    apiName: definition.apiName,
                    label: definition.label,
                    dataType,
                    required: definition.required === true,
                    value: this.normalizeMetadataValueForUi(rawValue, dataType),
                    isText: dataType === 'Text',
                    isNumber: dataType === 'Number',
                    isDate: dataType === 'Date',
                    isBoolean: dataType === 'Boolean'
                };
            });
        } catch (error) {
            this.metadataFields = [];
            throw error;
        } finally {
            if (manageState) {
                this.isBusy = false;
            }
        }
    }

    parseMetadataJsonMap(rawJson) {
        if (!rawJson) {
            return {};
        }

        try {
            const parsed = JSON.parse(rawJson);
            return parsed && typeof parsed === 'object' ? parsed : {};
        } catch (error) {
            return {};
        }
    }

    normalizeMetadataValueForUi(rawValue, dataType) {
        if (rawValue === null || rawValue === undefined) {
            return '';
        }

        if (dataType === 'Boolean') {
            if (rawValue === true || String(rawValue).toLowerCase() === 'true') {
                return 'true';
            }
            if (rawValue === false || String(rawValue).toLowerCase() === 'false') {
                return 'false';
            }
            return '';
        }

        return String(rawValue);
    }

    handleBaseFieldChange(event) {
        const field = event.target?.name;
        if (!field) {
            return;
        }

        const rawValue = event.detail?.value ?? event.target?.value ?? '';
        const value = field === 'amount' && rawValue !== '' ? Number(rawValue) : rawValue;

        if (field === 'workspace') {
            this.handleWorkspaceSelectionChange(rawValue);
            return;
        }

        this.form = {
            ...this.form,
            [field]: rawValue === '' && field === 'amount' ? null : value
        };

        this.result = null;
    }

    async handleWorkspaceSelectionChange(workspaceKey) {
        const selectedWorkspace = String(workspaceKey || '').trim();
        if (!selectedWorkspace || selectedWorkspace === this.form.workspace) {
            return;
        }

        const previousForm = { ...this.form };
        const previousContextData = this.contextData;
        const previousExistingLinkResult = this.existingLinkResult ? { ...this.existingLinkResult } : null;
        const previousMetadataFields = this.metadataFields.map((field) => ({ ...field }));

        this.form = {
            ...this.form,
            workspace: selectedWorkspace
        };
        this.result = null;
        this.isBusy = true;
        this.statusMessage = `Cargando mapping para ${selectedWorkspace}...`;

        try {
            const context = await getMappedRecordContext({
                recordId: this.recordId,
                objectApiName: this.objectApiName,
                workspace: selectedWorkspace
            });
            this.contextData = context;
            this.applyMappedContext(context);

            const initialMetadataValues = this.parseMetadataJsonMap(context?.existingMetadataJson);
            const resolvedWorkspace = String(this.form.workspace || selectedWorkspace).trim();
            await this.loadMetadataFieldDefinitions(resolvedWorkspace, initialMetadataValues, false);
            this.statusMessage = context?.message || `Mapping cargado para ${resolvedWorkspace}.`;
        } catch (error) {
            this.form = previousForm;
            this.contextData = previousContextData;
            this.existingLinkResult = previousExistingLinkResult;
            this.metadataFields = previousMetadataFields;
            this.statusMessage = this.getErrorMessage(error);
            this.showToast('Generate Payment Link', this.statusMessage, 'error');
        } finally {
            this.isBusy = false;
        }
    }

    async loadWorkspaceMetadata() {
        this.isBusy = true;
        this.statusMessage = 'Cargando metadata dinamica...';

        try {
            await this.loadMetadataFieldDefinitions(this.form.workspace, null, false);
            this.statusMessage = `Metadata cargada: ${this.metadataFields.length} campos.`;
        } catch (error) {
            this.statusMessage = 'No se pudo cargar metadata del workspace seleccionado.';
            this.showToast('Generate Payment Link', this.getErrorMessage(error), 'error');
        } finally {
            this.isBusy = false;
        }
    }

    handleMetadataChange(event) {
        const apiName = event.target?.dataset?.apiName;
        if (!apiName) {
            return;
        }

        const value = event.detail?.value ?? event.target?.value ?? '';
        this.metadataFields = this.metadataFields.map((field) =>
            field.apiName === apiName
                ? {
                      ...field,
                      value
                  }
                : field
        );
        this.result = null;
    }

    validateForm(formValues = this.form) {
        const values = formValues || {};

        if (!String(values.reference || '').trim()) {
            return 'Reference es obligatorio.';
        }
        if (values.amount === null || values.amount === undefined || Number(values.amount) <= 0) {
            return 'Amount debe ser mayor a cero.';
        }
        if (!String(values.currency || '').trim()) {
            return 'Currency es obligatorio.';
        }
        if (!String(values.concept || '').trim()) {
            return 'Concept es obligatorio.';
        }
        if (!String(values.customerName || '').trim()) {
            return 'Customer Name es obligatorio.';
        }
        if (!String(values.workspace || '').trim()) {
            return 'Workspace es obligatorio.';
        }

        for (const field of this.metadataFields) {
            if (field.required && (field.value === null || field.value === undefined || String(field.value).trim() === '')) {
                return `Metadata requerida: ${field.label}.`;
            }
            if (field.isNumber && String(field.value || '').trim() !== '' && Number.isNaN(Number(field.value))) {
                return `Metadata invalida (${field.label}): debe ser numero.`;
            }
        }

        return null;
    }

    buildMetadataJson() {
        const payload = {};

        for (const field of this.metadataFields) {
            const hasValue = field.value !== null && field.value !== undefined && String(field.value).trim() !== '';
            if (!hasValue) {
                continue;
            }

            if (field.isNumber) {
                payload[field.apiName] = Number(field.value);
                continue;
            }

            if (field.isBoolean) {
                payload[field.apiName] = field.value === 'true';
                continue;
            }

            payload[field.apiName] = field.value;
        }

        return Object.keys(payload).length === 0 ? null : JSON.stringify(payload);
    }

    getCurrentBaseFieldValue(fieldName) {
        const inputByName = this.template.querySelector(`[name="${fieldName}"]`);
        const inputByDataField = this.template.querySelector(`[data-field="${fieldName}"]`);
        const input = inputByName || inputByDataField;
        if (!input) {
            return this.form[fieldName];
        }

        return input.value;
    }

    getCurrentFormSnapshot() {
        const amountValue = this.getCurrentBaseFieldValue('amount');
        return {
            reference: String(this.getCurrentBaseFieldValue('reference') || '').trim(),
            amount:
                amountValue === '' || amountValue === null || amountValue === undefined
                    ? null
                    : Number(amountValue),
            currency: String(this.getCurrentBaseFieldValue('currency') || '').trim(),
            concept: String(this.getCurrentBaseFieldValue('concept') || '').trim(),
            customerName: String(this.getCurrentBaseFieldValue('customerName') || '').trim(),
            workspace: String(this.getCurrentBaseFieldValue('workspace') || '').trim()
        };
    }

    syncFormFromInputs() {
        const fields = ['reference', 'amount', 'currency', 'concept', 'customerName', 'workspace'];
        const updates = {};

        fields.forEach((fieldName) => {
            const input = this.template.querySelector(`[data-field="${fieldName}"]`);
            if (!input) {
                return;
            }

            const value = input.value;
            if (fieldName === 'amount') {
                updates[fieldName] = value === '' || value === null || value === undefined ? null : Number(value);
                return;
            }

            updates[fieldName] = value;
        });

        if (Object.keys(updates).length > 0) {
            this.form = {
                ...this.form,
                ...updates
            };
        }
    }

    syncMetadataFromInputs() {
        const valueByApiName = new Map();
        const metadataInputs = this.template.querySelectorAll('[data-api-name]');

        metadataInputs.forEach((input) => {
            const apiName = input?.dataset?.apiName;
            if (!apiName) {
                return;
            }
            valueByApiName.set(apiName, input.value);
        });

        if (valueByApiName.size === 0) {
            return;
        }

        this.metadataFields = this.metadataFields.map((field) =>
            valueByApiName.has(field.apiName)
                ? {
                      ...field,
                      value: valueByApiName.get(field.apiName)
                  }
                : field
        );
    }

    async handleGeneratePaymentLink() {
        // Temporal debug logs requested to confirm context values before save.
        // eslint-disable-next-line no-console
        console.log('recordId', this.recordId);
        // eslint-disable-next-line no-console
        console.log('objectApiName', this.objectApiName);

        if (!this.recordId || !this.objectApiName) {
            this.statusMessage = 'No se recibio contexto de registro (recordId/objectApiName).';
            this.showToast('Generate Payment Link', this.statusMessage, 'error');
            return;
        }

        const formSnapshot = this.getCurrentFormSnapshot();
        this.form = {
            ...this.form,
            ...formSnapshot
        };
        this.syncMetadataFromInputs();

        const validationError = this.validateForm(formSnapshot);
        if (validationError) {
            this.statusMessage = validationError;
            this.showToast('Generate Payment Link', validationError, 'error');
            return;
        }

        this.isBusy = true;
        this.statusMessage = 'Generando liga de pago...';

        try {
            const response = await generateFromMappedRecordDirect({
                recordId: this.recordId || this.contextData?.recordId || null,
                objectApiName: this.objectApiName || this.contextData?.objectApiName || null,
                reference: formSnapshot.reference,
                amount: formSnapshot.amount,
                currencyCode: formSnapshot.currency,
                concept: formSnapshot.concept,
                customerName: formSnapshot.customerName,
                workspace: formSnapshot.workspace,
                metadataJson: this.buildMetadataJson()
            });
            this.result = {
                paymentLinkId: response.paymentLinkId,
                paymentUrl: response.paymentUrl,
                status: response.status,
                workspace: response.workspace,
                currency: response.currencyCode,
                metadataJson: response.metadataJson,
                metadataIndex: response.metadataIndex,
                wasExisting: response.wasExisting === true,
                message: response.message
            };

            const reusedReference = response.wasExisting === true;
            this.statusMessage =
                response.message ||
                (reusedReference
                    ? 'Ya existe una liga con esa referencia. Se reutilizo la liga existente.'
                    : `Liga generada. Estatus: ${response.status}`);
            this.showToast('Generate Payment Link', this.statusMessage, reusedReference ? 'warning' : 'success');
        } catch (error) {
            this.statusMessage = 'No se pudo generar la liga.';
            this.showToast('Generate Payment Link', this.getErrorMessage(error), 'error');
        } finally {
            this.isBusy = false;
        }
    }

    handleCopyLink() {
        const url = this.activeResult?.paymentUrl;
        if (!url) {
            return;
        }

        if (navigator?.clipboard?.writeText) {
            navigator.clipboard
                .writeText(url)
                .then(() => {
                    this.showToast('Generate Payment Link', 'Liga copiada al portapapeles.', 'success');
                })
                .catch(() => {
                    this.showToast('Generate Payment Link', 'No se pudo copiar la liga.', 'error');
                });
            return;
        }

        this.showToast('Generate Payment Link', 'Copiado no disponible en este navegador.', 'warning');
    }

    handleSendViaWhatsApp() {
        const targetUrl = this.whatsAppUrl;
        if (!targetUrl) {
            return;
        }
        window.open(targetUrl, '_blank');
    }

    handleSendViaEmail() {
        const targetUrl = this.emailUrl;
        if (!targetUrl) {
            return;
        }
        window.open(targetUrl, '_blank');
    }

    handleClose() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    get hasMetadataFields() {
        return this.metadataFields.length > 0;
    }

    get activeResult() {
        return this.result || this.existingLinkResult;
    }

    get hasActiveResult() {
        return this.activeResult !== null;
    }

    get activeResultTitle() {
        if (!this.activeResult) {
            return '';
        }
        return this.result ? 'Generated Payment Link' : 'Existing Payment Link';
    }

    get canShareLink() {
        return Boolean(this.activeResult?.paymentUrl);
    }

    get whatsAppUrl() {
        const url = this.activeResult?.paymentUrl;
        if (!url) {
            return '';
        }

        const message =
            'Hola, aqui esta tu liga de pago: ' +
            url +
            (this.form.reference ? ' (Referencia: ' + this.form.reference + ')' : '');
        return 'https://wa.me/?text=' + encodeURIComponent(message);
    }

    get emailUrl() {
        const url = this.activeResult?.paymentUrl;
        if (!url) {
            return '';
        }

        const subject = 'Payment Link ' + (this.form.reference || '');
        const body =
            'Hola,\n\nComparte esta liga de pago:\n' +
            url +
            '\n\nReferencia: ' +
            (this.form.reference || '') +
            '\n';

        return 'mailto:?subject=' + encodeURIComponent(subject) + '&body=' + encodeURIComponent(body);
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }

    getErrorMessage(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (error?.message) {
            return error.message;
        }
        return 'Ocurrio un error inesperado.';
    }
}
