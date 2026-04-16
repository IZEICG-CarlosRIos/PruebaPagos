import { api, LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getWorkspaceOptions from '@salesforce/apex/GetNetPaymentUiFacade.getWorkspaceOptions';
import getQuickPaymentFieldDefinitions from '@salesforce/apex/GetNetPaymentUiFacade.getQuickPaymentFieldDefinitions';
import generateQuickPaymentDirect from '@salesforce/apex/GetNetPaymentUiFacade.generateQuickPaymentDirect';

export default class GetnetQuickPayment extends LightningElement {
    quickPaymentStatusMessage = 'Completa los datos para generar la liga.';
    isQuickPaymentBusy = false;
    quickPaymentWorkspaceOptions = [];
    quickPaymentMetadataFields = [];
    quickPaymentResult = null;

    quickPaymentForm = {
        reference: '',
        amount: null,
        currency: 'MXN',
        concept: '',
        customerName: '',
        workspace: '',
        metadataJson: ''
    };

    currencyOptions = [
        { label: 'MXN', value: 'MXN' },
        { label: 'USD', value: 'USD' }
    ];

    quickPaymentBooleanOptions = [
        { label: 'Select', value: '' },
        { label: 'True', value: 'true' },
        { label: 'False', value: 'false' }
    ];

    connectedCallback() {
        this.loadQuickPaymentWorkspaceOptions();
    }

    @api
    refreshWorkspaceOptions() {
        return this.loadQuickPaymentWorkspaceOptions();
    }

    handleQuickPaymentChange(event) {
        const field = event.target?.name || event.target?.dataset?.field;
        if (!field) {
            return;
        }

        const value = event.detail?.value ?? event.target?.value ?? '';
        this.quickPaymentForm = {
            ...this.quickPaymentForm,
            [field]: value
        };

        if (field === 'workspace') {
            this.loadQuickPaymentFieldDefinitions(value);
        }

        this.quickPaymentResult = null;
    }

    async loadQuickPaymentWorkspaceOptions() {
        try {
            const options = await getWorkspaceOptions({});
            this.quickPaymentWorkspaceOptions = (options || []).map((option) => ({
                label: option.label,
                value: option.value
            }));

            if (!this.quickPaymentForm.workspace && this.quickPaymentWorkspaceOptions.length > 0) {
                this.quickPaymentForm = {
                    ...this.quickPaymentForm,
                    workspace: this.quickPaymentWorkspaceOptions[0].value
                };
            }

            if (
                this.quickPaymentForm.workspace &&
                !this.quickPaymentWorkspaceOptions.some((option) => option.value === this.quickPaymentForm.workspace)
            ) {
                this.quickPaymentForm = {
                    ...this.quickPaymentForm,
                    workspace:
                        this.quickPaymentWorkspaceOptions.length > 0 ? this.quickPaymentWorkspaceOptions[0].value : ''
                };
            }

            if (this.quickPaymentForm.workspace) {
                await this.loadQuickPaymentFieldDefinitions(this.quickPaymentForm.workspace);
            } else {
                this.quickPaymentMetadataFields = [];
                this.quickPaymentStatusMessage = 'No hay workspaces configurados para Quick Payment.';
            }
        } catch (error) {
            this.quickPaymentStatusMessage = 'No se pudieron cargar workspaces de Quick Payment.';
            this.showToast('Quick Payment', this.getErrorMessage(error), 'error');
        }
    }

    async loadQuickPaymentFieldDefinitions(workspaceKey) {
        if (!workspaceKey) {
            this.quickPaymentMetadataFields = [];
            this.quickPaymentStatusMessage = 'Selecciona un workspace para cargar metadata dinamica.';
            return;
        }

        this.isQuickPaymentBusy = true;
        this.quickPaymentStatusMessage = `Cargando metadata para ${workspaceKey}...`;

        try {
            const defs = await getQuickPaymentFieldDefinitions({ workspaceKey });
            this.quickPaymentMetadataFields = (defs || []).map((fieldDef) => {
                const dataType = fieldDef.dataType || 'Text';
                return {
                    apiName: fieldDef.apiName,
                    label: fieldDef.label,
                    dataType,
                    required: fieldDef.required === true,
                    xmlTag: fieldDef.xmlTag,
                    sortOrder: fieldDef.sortOrder,
                    value: '',
                    isText: dataType === 'Text',
                    isNumber: dataType === 'Number',
                    isDate: dataType === 'Date',
                    isBoolean: dataType === 'Boolean'
                };
            });

            this.quickPaymentStatusMessage = `Metadata cargada: ${this.quickPaymentMetadataFields.length} campos.`;
        } catch (error) {
            this.quickPaymentMetadataFields = [];
            this.quickPaymentStatusMessage = 'No se pudo cargar metadata dinamica.';
            this.showToast('Quick Payment', this.getErrorMessage(error), 'error');
        } finally {
            this.isQuickPaymentBusy = false;
        }
    }

    handleQuickPaymentMetadataValueChange(event) {
        const apiName = event.target.dataset.apiName;
        const value = event.detail?.value ?? event.target?.value ?? '';
        this.quickPaymentMetadataFields = this.quickPaymentMetadataFields.map((field) =>
            field.apiName === apiName
                ? {
                      ...field,
                      value
                  }
                : field
        );
        this.quickPaymentResult = null;
    }

    validateQuickPaymentForm() {
        const errors = [];
        const reference = String(this.quickPaymentForm.reference || '').trim();
        const concept = String(this.quickPaymentForm.concept || '').trim();
        const customerName = String(this.quickPaymentForm.customerName || '').trim();
        const workspace = String(this.quickPaymentForm.workspace || '').trim();

        if (!reference) {
            errors.push('Reference es obligatorio.');
        }
        if (!this.quickPaymentForm.amount || Number(this.quickPaymentForm.amount) <= 0) {
            errors.push('Amount debe ser mayor a cero.');
        }
        if (!this.quickPaymentForm.currency) {
            errors.push('Currency es obligatorio.');
        }
        if (!concept) {
            errors.push('Concept es obligatorio.');
        }
        if (!customerName) {
            errors.push('Customer Name es obligatorio.');
        }
        if (!workspace) {
            errors.push('Workspace es obligatorio.');
        }

        for (const field of this.quickPaymentMetadataFields) {
            if (field.required && (field.value === null || field.value === undefined || field.value === '')) {
                errors.push(`Metadata requerida: ${field.label}.`);
            }
        }

        if (errors.length > 0) {
            this.showToast('Quick Payment', errors[0], 'error');
            this.quickPaymentStatusMessage = errors[0];
            return false;
        }

        return true;
    }

    buildQuickPaymentMetadataJson() {
        const values = {};
        for (const field of this.quickPaymentMetadataFields) {
            if (field.value === null || field.value === undefined || field.value === '') {
                continue;
            }
            values[field.apiName] = field.value;
        }
        return Object.keys(values).length === 0 ? null : JSON.stringify(values);
    }

    syncQuickPaymentFormFromInputs() {
        const fields = ['reference', 'amount', 'currency', 'concept', 'customerName', 'workspace'];
        const updates = {};

        fields.forEach((fieldName) => {
            const input = this.template.querySelector(`[data-field="${fieldName}"]`);
            if (!input) {
                return;
            }
            updates[fieldName] = input.value;
        });

        if (Object.keys(updates).length > 0) {
            this.quickPaymentForm = {
                ...this.quickPaymentForm,
                ...updates
            };
        }
    }

    syncQuickPaymentMetadataFromInputs() {
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

        this.quickPaymentMetadataFields = this.quickPaymentMetadataFields.map((field) =>
            valueByApiName.has(field.apiName)
                ? {
                      ...field,
                      value: valueByApiName.get(field.apiName)
                  }
                : field
        );
    }

    async handleQuickPaymentGenerate() {
        this.syncQuickPaymentFormFromInputs();
        this.syncQuickPaymentMetadataFromInputs();

        if (!this.validateQuickPaymentForm()) {
            return;
        }

        this.isQuickPaymentBusy = true;
        this.quickPaymentStatusMessage = 'Generando liga...';
        this.quickPaymentResult = null;

        try {
            const result = await generateQuickPaymentDirect({
                reference: String(this.quickPaymentForm.reference || '').trim(),
                amount: Number(this.quickPaymentForm.amount),
                currencyCode: this.quickPaymentForm.currency,
                concept: String(this.quickPaymentForm.concept || '').trim(),
                customerName: String(this.quickPaymentForm.customerName || '').trim(),
                workspace: String(this.quickPaymentForm.workspace || '').trim(),
                metadataJson: this.buildQuickPaymentMetadataJson()
            });
            this.quickPaymentResult = {
                paymentLinkId: result.paymentLinkId,
                paymentUrl: result.paymentUrl,
                status: result.status,
                workspace: result.workspace,
                currency: result.currencyCode,
                metadataJson: result.metadataJson,
                metadataIndex: result.metadataIndex,
                wasExisting: result.wasExisting === true
            };

            const reusedReference = result.wasExisting === true;
            this.quickPaymentStatusMessage =
                result.message ||
                (reusedReference
                    ? 'Ya existe una liga con esa referencia. Se reutilizo la liga existente.'
                    : `Liga generada. Estatus: ${result.status}`);
            this.showToast('Quick Payment', this.quickPaymentStatusMessage, reusedReference ? 'warning' : 'success');
        } catch (error) {
            this.quickPaymentStatusMessage = 'No se pudo generar la liga.';
            this.showToast('Quick Payment', this.getErrorMessage(error), 'error');
        } finally {
            this.isQuickPaymentBusy = false;
        }
    }

    get hasQuickPaymentMetadataFields() {
        return this.quickPaymentMetadataFields.length > 0;
    }

    get hasQuickPaymentResult() {
        return this.quickPaymentResult !== null;
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
