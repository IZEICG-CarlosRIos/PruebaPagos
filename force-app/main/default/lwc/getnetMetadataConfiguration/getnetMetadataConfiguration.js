import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getMetadataFieldConfigs from '@salesforce/apex/GetNetPaymentUiFacade.getMetadataFieldConfigs';
import getMetadataWorkspaceOptions from '@salesforce/apex/GetNetPaymentUiFacade.getMetadataWorkspaceOptions';
import saveMetadataFieldConfigDirect from '@salesforce/apex/GetNetPaymentUiFacade.saveMetadataFieldConfigDirect';
import deactivateMetadataFieldConfig from '@salesforce/apex/GetNetPaymentUiFacade.deactivateMetadataFieldConfig';

const NEW_WORKSPACE_OPTION_VALUE = '__NEW_WORKSPACE__';
const ALL_WORKSPACES_FILTER_VALUE = '__ALL_WORKSPACES__';

const METADATA_CONFIG_COLUMNS = [
    { label: 'Workspace', fieldName: 'workspace', type: 'text' },
    { label: 'Field Label', fieldName: 'fieldLabel', type: 'text' },
    { label: 'Field API Name', fieldName: 'fieldApiName', type: 'text' },
    { label: 'Data Type', fieldName: 'dataType', type: 'text' },
    { label: 'Required', fieldName: 'requiredLabel', type: 'text' },
    { label: 'XML Tag', fieldName: 'xmlTag', type: 'text' },
    { label: 'Sort Order', fieldName: 'sortOrder', type: 'number' },
    { label: 'Active', fieldName: 'activeLabel', type: 'text' },
    {
        type: 'action',
        typeAttributes: {
            rowActions: [
                { label: 'Edit', name: 'edit' },
                { label: 'Deactivate', name: 'deactivate' }
            ]
        }
    }
];

export default class GetnetMetadataConfiguration extends LightningElement {
    metadataConfigStatusMessage = 'Cargando configuraciones...';
    isMetadataConfigBusy = false;
    metadataWorkspaceOptions = [];
    metadataConfigRows = [];
    metadataWorkspaceFilter = ALL_WORKSPACES_FILTER_VALUE;
    metadataConfigColumns = METADATA_CONFIG_COLUMNS;

    metadataConfigForm = {
        developerName: '',
        workspace: '',
        workspaceSelection: '',
        newWorkspace: '',
        fieldLabel: '',
        fieldApiName: '',
        dataType: 'Text',
        required: false,
        xmlTag: '',
        sortOrder: null,
        active: true
    };

    dataTypeOptions = [
        { label: 'Text', value: 'Text' },
        { label: 'Number', value: 'Number' },
        { label: 'Date', value: 'Date' },
        { label: 'Boolean', value: 'Boolean' }
    ];

    connectedCallback() {
        this.initializeMetadataConfiguration();
    }

    handleMetadataConfigChange(event) {
        const field = event.target?.name;
        if (!field) {
            return;
        }

        const value =
            event.target.type === 'checkbox'
                ? event.target.checked
                : event.detail?.value ?? event.target?.value ?? '';
        if (field === 'workspaceSelection') {
            this.metadataConfigForm = {
                ...this.metadataConfigForm,
                workspaceSelection: value,
                workspace: value === NEW_WORKSPACE_OPTION_VALUE ? '' : value,
                newWorkspace: value === NEW_WORKSPACE_OPTION_VALUE ? this.metadataConfigForm.newWorkspace : ''
            };
            return;
        }

        if (field === 'newWorkspace') {
            this.metadataConfigForm = {
                ...this.metadataConfigForm,
                newWorkspace: value
            };
            return;
        }

        this.metadataConfigForm = {
            ...this.metadataConfigForm,
            [field]: value
        };
    }

    handleMetadataWorkspaceFilterChange(event) {
        this.metadataWorkspaceFilter = event.detail?.value || ALL_WORKSPACES_FILTER_VALUE;
    }

    async handleMetadataConfigRefresh() {
        this.isMetadataConfigBusy = true;
        this.metadataConfigStatusMessage = '';

        try {
            await Promise.all([this.loadMetadataConfigRows(false), this.loadMetadataWorkspaceOptions(false)]);
            this.resetMetadataConfigForm();
            this.metadataConfigStatusMessage = `Configuraciones actualizadas: ${this.metadataConfigRows.length}`;
            this.notifyMetadataChanged();
        } catch (error) {
            this.metadataConfigStatusMessage = 'No se pudo refrescar Metadata Configuration.';
            this.showToast('Metadata Configuration', this.getErrorMessage(error), 'error');
        } finally {
            this.isMetadataConfigBusy = false;
        }
    }

    handleMetadataConfigNew() {
        this.resetMetadataConfigForm();
        this.metadataConfigStatusMessage = 'Nuevo registro de metadata.';
    }

    handleMetadataConfigRowAction(event) {
        const actionName = event.detail?.action?.name;
        const row = event.detail?.row;

        if (actionName === 'edit') {
            this.metadataConfigForm = {
                developerName: row.developerName || '',
                workspace: row.workspace || '',
                workspaceSelection: row.workspace || '',
                newWorkspace: '',
                fieldLabel: row.fieldLabel || '',
                fieldApiName: row.fieldApiName || '',
                dataType: row.dataType || 'Text',
                required: row.required === true,
                xmlTag: row.xmlTag || '',
                sortOrder: row.sortOrder,
                active: row.active === true
            };
            this.metadataConfigStatusMessage = `Editando: ${row.developerName}`;
            return;
        }

        if (actionName === 'deactivate' && row?.developerName) {
            this.handleMetadataConfigDeactivate(row.developerName);
        }
    }

    async initializeMetadataConfiguration() {
        this.isMetadataConfigBusy = true;
        this.metadataConfigStatusMessage = 'Cargando configuraciones...';

        try {
            await Promise.all([this.loadMetadataConfigRows(false), this.loadMetadataWorkspaceOptions(false)]);
            this.metadataConfigStatusMessage = `Configuraciones cargadas: ${this.metadataConfigRows.length}`;
        } catch (error) {
            this.metadataConfigStatusMessage = 'No se pudieron cargar configuraciones.';
            this.showToast('Metadata Configuration', this.getErrorMessage(error), 'error');
        } finally {
            this.isMetadataConfigBusy = false;
        }
    }

    async loadMetadataConfigRows(manageState = true) {
        if (manageState) {
            this.isMetadataConfigBusy = true;
            this.metadataConfigStatusMessage = 'Cargando configuraciones...';
        }

        try {
            const rows = await getMetadataFieldConfigs({ workspaceKey: null });
            const mappedRows = (rows || []).map((row) => ({
                id: row.developerName,
                developerName: row.developerName,
                workspace: row.workspace,
                fieldLabel: row.fieldLabel,
                fieldApiName: row.fieldApiName,
                dataType: row.dataType,
                required: row.required === true,
                requiredLabel: row.required ? 'Yes' : 'No',
                xmlTag: row.xmlTag,
                sortOrder: row.sortOrder,
                active: row.active === true,
                activeLabel: row.active ? 'Yes' : 'No'
            }));
            this.metadataConfigRows = [...mappedRows];

            if (manageState) {
                this.metadataConfigStatusMessage = `Configuraciones cargadas: ${this.metadataConfigRows.length}`;
            }
        } catch (error) {
            if (manageState) {
                this.metadataConfigStatusMessage = 'No se pudieron cargar configuraciones.';
                this.showToast('Metadata Configuration', this.getErrorMessage(error), 'error');
            }
            throw error;
        } finally {
            if (manageState) {
                this.isMetadataConfigBusy = false;
            }
        }
    }

    async loadMetadataWorkspaceOptions(manageState = true) {
        if (manageState) {
            this.isMetadataConfigBusy = true;
        }

        try {
            const options = await getMetadataWorkspaceOptions({});
            const mappedOptions = (options || []).map((option) => ({
                label: option.label,
                value: option.value
            }));
            this.metadataWorkspaceOptions = [...mappedOptions];
        } catch (error) {
            if (manageState) {
                this.showToast('Metadata Configuration', this.getErrorMessage(error), 'error');
            }
            throw error;
        } finally {
            if (manageState) {
                this.isMetadataConfigBusy = false;
            }
        }
    }

    async handleMetadataConfigSave() {
        this.isMetadataConfigBusy = true;
        this.metadataConfigStatusMessage = 'Guardando configuracion...';

        try {
            const metadataFormPayload = { ...this.metadataConfigForm };
            const resolvedWorkspace = this.resolveMetadataWorkspace(metadataFormPayload);
            const validationError = this.validateMetadataConfigForm(metadataFormPayload, resolvedWorkspace);
            if (validationError) {
                this.metadataConfigStatusMessage = validationError;
                this.showToast('Metadata Configuration', validationError, 'error');
                return;
            }

            const request = {
                developerName: metadataFormPayload.developerName || null,
                workspace: resolvedWorkspace,
                fieldLabel: String(metadataFormPayload.fieldLabel || '').trim(),
                fieldApiName: String(metadataFormPayload.fieldApiName || '').trim(),
                dataType: String(metadataFormPayload.dataType || '').trim(),
                required: metadataFormPayload.required === true,
                xmlTag: String(metadataFormPayload.xmlTag || '').trim(),
                sortOrder: this.parseIntegerOrNull(metadataFormPayload.sortOrder),
                active: metadataFormPayload.active === true
            };

            const result = await saveMetadataFieldConfigDirect({
                developerName: request.developerName,
                workspace: request.workspace,
                fieldLabel: request.fieldLabel,
                fieldApiName: request.fieldApiName,
                dataType: request.dataType,
                required: request.required,
                xmlTag: request.xmlTag,
                sortOrder: request.sortOrder,
                active: request.active
            });
            const success = result?.success === true;

            if (!success) {
                const failureMessage = result?.message || 'No se pudo guardar configuracion.';
                this.metadataConfigStatusMessage = failureMessage;
                this.showToast('Metadata Configuration', failureMessage, 'error');
                return;
            }

            this.metadataConfigStatusMessage = `Configuracion guardada (${result.developerName}). Estado: ${result.deploymentStatus}`;
            this.showToast('Metadata Configuration', this.metadataConfigStatusMessage, 'success');

            await this.loadMetadataConfigRows(false);
            await this.loadMetadataWorkspaceOptions(false);
            this.notifyMetadataChanged();

            const updatedRow = this.metadataConfigRows.find((row) => row.developerName === result.developerName);
            if (updatedRow) {
                this.metadataConfigForm = {
                    developerName: updatedRow.developerName || '',
                    workspace: updatedRow.workspace || '',
                    workspaceSelection: updatedRow.workspace || '',
                    newWorkspace: '',
                    fieldLabel: updatedRow.fieldLabel || '',
                    fieldApiName: updatedRow.fieldApiName || '',
                    dataType: updatedRow.dataType || 'Text',
                    required: updatedRow.required === true,
                    xmlTag: updatedRow.xmlTag || '',
                    sortOrder: updatedRow.sortOrder,
                    active: updatedRow.active === true
                };
            }
        } catch (error) {
            this.metadataConfigStatusMessage = 'No se pudo guardar configuracion.';
            this.showToast('Metadata Configuration', this.getErrorMessage(error), 'error');
        } finally {
            this.isMetadataConfigBusy = false;
        }
    }

    async handleMetadataConfigDeactivate(developerName) {
        this.isMetadataConfigBusy = true;
        this.metadataConfigStatusMessage = `Desactivando ${developerName}...`;

        try {
            const result = await deactivateMetadataFieldConfig({ developerName });
            const success = result?.success === true;
            if (!success) {
                const failureMessage = result?.message || 'No se pudo desactivar configuracion.';
                this.metadataConfigStatusMessage = failureMessage;
                this.showToast('Metadata Configuration', failureMessage, 'error');
                return;
            }

            this.metadataConfigStatusMessage = `Desactivacion enviada (${developerName}). Estado: ${result.deploymentStatus}`;
            this.showToast('Metadata Configuration', this.metadataConfigStatusMessage, 'success');
            await this.loadMetadataConfigRows(false);
            await this.loadMetadataWorkspaceOptions(false);
            this.notifyMetadataChanged();

            if (this.metadataConfigForm.developerName === developerName) {
                this.resetMetadataConfigForm();
            }
        } catch (error) {
            this.metadataConfigStatusMessage = 'No se pudo desactivar configuracion.';
            this.showToast('Metadata Configuration', this.getErrorMessage(error), 'error');
        } finally {
            this.isMetadataConfigBusy = false;
        }
    }

    resetMetadataConfigForm() {
        this.metadataConfigForm = {
            developerName: '',
            workspace: '',
            workspaceSelection: '',
            newWorkspace: '',
            fieldLabel: '',
            fieldApiName: '',
            dataType: 'Text',
            required: false,
            xmlTag: '',
            sortOrder: null,
            active: true
        };
    }

    resolveMetadataWorkspace(form) {
        const values = form || {};
        if (values.workspaceSelection === NEW_WORKSPACE_OPTION_VALUE) {
            return String(values.newWorkspace || '').trim();
        }

        if (!String(values.workspaceSelection || '').trim()) {
            return String(values.workspace || '').trim();
        }

        return String(values.workspaceSelection || '').trim();
    }

    validateMetadataConfigForm(form, resolvedWorkspace) {
        const values = form || {};
        if (values.workspaceSelection === NEW_WORKSPACE_OPTION_VALUE && !String(values.newWorkspace || '').trim()) {
            return 'Nuevo Workspace es obligatorio cuando seleccionas "Nuevo workspace...".';
        }

        if (!String(resolvedWorkspace || '').trim()) {
            return 'Workspace es obligatorio.';
        }
        if (!String(values.fieldLabel || '').trim()) {
            return 'Field Label es obligatorio.';
        }
        if (!String(values.fieldApiName || '').trim()) {
            return 'Field API Name es obligatorio.';
        }
        if (!String(values.dataType || '').trim()) {
            return 'Data Type es obligatorio.';
        }

        if (values.sortOrder !== null && values.sortOrder !== undefined && values.sortOrder !== '') {
            const parsed = Number.parseInt(values.sortOrder, 10);
            if (Number.isNaN(parsed)) {
                return 'Sort Order debe ser numerico.';
            }
        }

        return null;
    }

    get metadataWorkspaceComboboxOptions() {
        return [...this.metadataWorkspaceOptions, { label: 'Nuevo workspace...', value: NEW_WORKSPACE_OPTION_VALUE }];
    }

    get metadataWorkspaceFilterOptions() {
        const optionMap = new Map();

        (this.metadataWorkspaceOptions || []).forEach((option) => {
            const value = String(option?.value || '').trim();
            if (value) {
                optionMap.set(value, option?.label || value);
            }
        });

        (this.metadataConfigRows || []).forEach((row) => {
            const value = String(row?.workspace || '').trim();
            if (value && !optionMap.has(value)) {
                optionMap.set(value, value);
            }
        });

        return [
            { label: 'Todos los workspaces', value: ALL_WORKSPACES_FILTER_VALUE },
            ...Array.from(optionMap.entries()).map(([value, label]) => ({ label, value }))
        ];
    }

    get filteredMetadataConfigRows() {
        if (this.metadataWorkspaceFilter === ALL_WORKSPACES_FILTER_VALUE) {
            return this.metadataConfigRows;
        }

        return (this.metadataConfigRows || []).filter(
            (row) => String(row?.workspace || '').trim() === this.metadataWorkspaceFilter
        );
    }

    get isNewMetadataWorkspaceSelected() {
        return this.metadataConfigForm.workspaceSelection === NEW_WORKSPACE_OPTION_VALUE;
    }

    parseIntegerOrNull(value) {
        if (value === null || value === undefined || value === '') {
            return null;
        }
        const parsed = Number.parseInt(value, 10);
        return Number.isNaN(parsed) ? null : parsed;
    }

    notifyMetadataChanged() {
        this.dispatchEvent(new CustomEvent('metadatachanged'));
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
