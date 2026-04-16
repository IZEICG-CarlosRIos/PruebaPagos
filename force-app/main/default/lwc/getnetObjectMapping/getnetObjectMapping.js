import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getObjectMappingObjectOptions from '@salesforce/apex/GetNetPaymentUiFacade.getObjectMappingObjectOptions';
import getObjectMappingFieldOptions from '@salesforce/apex/GetNetPaymentUiFacade.getObjectMappingFieldOptions';
import getObjectMappings from '@salesforce/apex/GetNetPaymentUiFacade.getObjectMappings';
import getWorkspaceOptions from '@salesforce/apex/GetNetPaymentUiFacade.getWorkspaceOptions';
import saveObjectMappingDirectV2 from '@salesforce/apex/GetNetPaymentUiFacade.saveObjectMappingDirectV2';
import activateObjectMapping from '@salesforce/apex/GetNetPaymentUiFacade.activateObjectMapping';
import deleteObjectMapping from '@salesforce/apex/GetNetPaymentUiFacade.deleteObjectMapping';

const DEFAULT_CONFIG_NAME = 'ConfiguracionPrueba';
const ALL_WORKSPACES_FILTER_VALUE = '__ALL_WORKSPACES__';

const MAPPING_COLUMNS = [
    { label: 'Developer Name', fieldName: 'developerName', type: 'text' },
    { label: 'Object', fieldName: 'objectApiName', type: 'text' },
    { label: 'Reference Field', fieldName: 'referenceField', type: 'text' },
    { label: 'Amount Field', fieldName: 'amountField', type: 'text' },
    { label: 'Currency', fieldName: 'currency', type: 'text' },
    { label: 'Workspace', fieldName: 'workspace', type: 'text' },
    { label: 'Status', fieldName: 'status', type: 'text' },
    {
        type: 'action',
        typeAttributes: {
            rowActions: [
                { label: 'Edit', name: 'edit' },
                { label: 'Activate', name: 'activate' },
                { label: 'Delete', name: 'delete' }
            ]
        }
    }
];

export default class GetnetObjectMapping extends LightningElement {
    mappingStatusMessage = 'Cargando mappings...';
    isMappingBusy = false;
    mappingObjectOptions = [];
    mappingWorkspaceOptions = [];
    mappingReferenceFieldOptions = [];
    mappingAmountFieldOptions = [];

    mappingForm = {
        developerName: '',
        objectApiName: '',
        referenceField: '',
        amountField: '',
        currency: '',
        workspace: DEFAULT_CONFIG_NAME,
        active: false
    };

    mappingColumns = MAPPING_COLUMNS;
    mappingRows = [];
    mappingWorkspaceFilter = ALL_WORKSPACES_FILTER_VALUE;
    pendingDeletedDeveloperNames = new Set();

    currencyOptions = [
        { label: 'MXN', value: 'MXN' },
        { label: 'USD', value: 'USD' }
    ];

    connectedCallback() {
        this.initializeObjectMapping();
    }

    handleMappingChange(event) {
        const field = event.target?.name;
        if (!field) {
            return;
        }

        const value =
            event.target?.type === 'checkbox'
                ? event.target.checked
                : event.detail?.value ?? event.target?.value ?? '';
        this.mappingForm = {
            ...this.mappingForm,
            [field]: value
        };

        if (field === 'objectApiName') {
            this.mappingForm = {
                ...this.mappingForm,
                objectApiName: value,
                referenceField: '',
                amountField: ''
            };
            this.loadObjectMappingFieldOptions(value);
        }
    }

    handleMappingWorkspaceFilterChange(event) {
        this.mappingWorkspaceFilter = event.detail?.value || ALL_WORKSPACES_FILTER_VALUE;
    }

    handleMappingNew() {
        const fallbackWorkspace =
            this.mappingForm.workspace ||
            (this.mappingWorkspaceOptions.length > 0 ? this.mappingWorkspaceOptions[0].value : DEFAULT_CONFIG_NAME);
        this.mappingForm = this.buildNewMappingForm(fallbackWorkspace);
        this.mappingReferenceFieldOptions = [];
        this.mappingAmountFieldOptions = [];
        this.mappingStatusMessage = 'Nuevo mapping listo. Se guardara desactivado por defecto.';
    }

    async initializeObjectMapping() {
        this.isMappingBusy = true;
        this.mappingStatusMessage = 'Cargando mappings...';

        try {
            await Promise.all([
                this.loadObjectMappingObjects(false),
                this.loadObjectMappings(false),
                this.loadMappingWorkspaceOptions(false)
            ]);
            this.mappingStatusMessage = `Mappings cargados: ${this.mappingRows.length}`;
        } catch (error) {
            this.mappingStatusMessage = 'No se pudo cargar Object Mapping.';
            this.showToast('Object Mapping', this.getErrorMessage(error), 'error');
        } finally {
            this.isMappingBusy = false;
        }
    }

    async loadObjectMappingObjects(manageState = true) {
        if (manageState) {
            this.isMappingBusy = true;
        }

        try {
            const options = await getObjectMappingObjectOptions({});
            const mappedOptions = (options || []).map((option) => ({
                label: option.label,
                value: option.value
            }));
            this.mappingObjectOptions = [...mappedOptions];
        } catch (error) {
            if (manageState) {
                this.showToast('Object Mapping', this.getErrorMessage(error), 'error');
            }
            throw error;
        } finally {
            if (manageState) {
                this.isMappingBusy = false;
            }
        }
    }

    async loadMappingWorkspaceOptions(manageState = true) {
        if (manageState) {
            this.isMappingBusy = true;
        }

        try {
            const options = await getWorkspaceOptions({});
            const mappedOptions = (options || []).map((option) => ({
                label: option.label,
                value: option.value
            }));

            this.mappingWorkspaceOptions = [...mappedOptions];
            if (this.mappingWorkspaceOptions.length === 0) {
                this.mappingWorkspaceOptions = [{ label: DEFAULT_CONFIG_NAME, value: DEFAULT_CONFIG_NAME }];
            }

            const selectedWorkspace = String(this.mappingForm.workspace || '').trim();
            const hasSelectedWorkspace = this.mappingWorkspaceOptions.some((option) => option.value === selectedWorkspace);
            if (!hasSelectedWorkspace) {
                this.mappingForm = {
                    ...this.mappingForm,
                    workspace: this.mappingWorkspaceOptions[0].value
                };
            }
        } catch (error) {
            if (manageState) {
                this.showToast('Object Mapping', this.getErrorMessage(error), 'error');
            }
            throw error;
        } finally {
            if (manageState) {
                this.isMappingBusy = false;
            }
        }
    }

    async loadObjectMappings(manageState = true) {
        if (manageState) {
            this.isMappingBusy = true;
            this.mappingStatusMessage = 'Cargando mappings...';
        }

        try {
            const rows = await getObjectMappings({});
            const mappedRows = (rows || []).map((row) => ({
                id: row.id || row.developerName,
                developerName: row.developerName,
                objectApiName: row.objectApiName,
                referenceField: row.referenceField,
                amountField: row.amountField,
                currency: row.currencyCode,
                workspace: row.workspace || DEFAULT_CONFIG_NAME,
                active: row.active === true,
                status: row.status || 'Active'
            }));

            const returnedDeveloperNames = new Set(mappedRows.map((row) => row.developerName));
            this.pendingDeletedDeveloperNames.forEach((developerName) => {
                if (!returnedDeveloperNames.has(developerName)) {
                    this.pendingDeletedDeveloperNames.delete(developerName);
                }
            });

            this.mappingRows = mappedRows.filter(
                (row) => !this.pendingDeletedDeveloperNames.has(row.developerName)
            );

            if (manageState) {
                this.mappingStatusMessage = `Mappings cargados: ${this.mappingRows.length}`;
            }
        } catch (error) {
            if (manageState) {
                this.mappingStatusMessage = 'No se pudieron cargar mappings.';
                this.showToast('Object Mapping', this.getErrorMessage(error), 'error');
            }
            throw error;
        } finally {
            if (manageState) {
                this.isMappingBusy = false;
            }
        }
    }

    async loadObjectMappingFieldOptions(objectApiName, manageState = true) {
        if (String(objectApiName || '').trim() === '') {
            this.mappingReferenceFieldOptions = [];
            this.mappingAmountFieldOptions = [];
            return;
        }

        if (manageState) {
            this.isMappingBusy = true;
        }

        try {
            const response = await getObjectMappingFieldOptions({ objectApiName });
            const mappedReferenceOptions = (response?.referenceFieldOptions || []).map((option) => ({
                label: option.label,
                value: option.value
            }));
            const mappedAmountOptions = (response?.amountFieldOptions || []).map((option) => ({
                label: option.label,
                value: option.value
            }));
            this.mappingReferenceFieldOptions = [...mappedReferenceOptions];
            this.mappingAmountFieldOptions = [...mappedAmountOptions];

            if (manageState) {
                if (mappedReferenceOptions.length === 0 && mappedAmountOptions.length === 0) {
                    this.mappingStatusMessage =
                        `El objeto ${objectApiName} no tiene campos válidos para Reference Field ni Amount Field.`;
                } else if (mappedReferenceOptions.length === 0) {
                    this.mappingStatusMessage =
                        `El objeto ${objectApiName} no tiene campos válidos para Reference Field.`;
                } else if (mappedAmountOptions.length === 0) {
                    this.mappingStatusMessage =
                        `El objeto ${objectApiName} no tiene campos válidos para Amount Field.`;
                } else {
                    this.mappingStatusMessage =
                        `Campos de mapping cargados para ${objectApiName}.`;
                }
            }
        } catch (error) {
            this.mappingReferenceFieldOptions = [];
            this.mappingAmountFieldOptions = [];
            if (manageState) {
                this.showToast('Object Mapping', this.getErrorMessage(error), 'error');
            }
            throw error;
        } finally {
            if (manageState) {
                this.isMappingBusy = false;
            }
        }
    }

    validateMappingForm(form) {
        const values = form || {};
        if (!String(values.objectApiName || '').trim()) {
            return 'Object es obligatorio.';
        }
        if (!String(values.referenceField || '').trim()) {
            return 'Reference Field es obligatorio.';
        }
        if (!String(values.amountField || '').trim()) {
            return 'Amount Field es obligatorio.';
        }
        if (!String(values.currency || '').trim()) {
            return 'Currency es obligatorio.';
        }
        if (!String(values.workspace || '').trim()) {
            return 'Workspace es obligatorio.';
        }
        return null;
    }

    async handleObjectMappingSave() {
        this.isMappingBusy = true;
        this.mappingStatusMessage = 'Guardando mapping...';

        try {
            const payload = { ...this.mappingForm };
            payload.active = payload.active === true;
            const validationError = this.validateMappingForm(payload);
            if (validationError) {
                this.mappingStatusMessage = validationError;
                this.showToast('Object Mapping', validationError, 'error');
                return;
            }

            const result = await saveObjectMappingDirectV2({
                developerName: String(payload.developerName || '').trim() || null,
                objectApiName: payload.objectApiName,
                referenceField: payload.referenceField,
                amountField: payload.amountField,
                currencyCode: payload.currency,
                workspace: payload.workspace,
                active: payload.active
            });

            const success = result?.success === true;
            if (!success) {
                const message = result?.message || 'No se pudo guardar mapping.';
                this.mappingStatusMessage = message;
                this.showToast('Object Mapping', message, 'error');
                return;
            }

            const savedRow = {
                id: result.developerName,
                developerName: result.developerName,
                objectApiName: payload.objectApiName,
                referenceField: payload.referenceField,
                amountField: payload.amountField,
                currency: payload.currency,
                workspace: payload.workspace,
                active: payload.active === true,
                status: payload.active === true ? 'Active' : 'Inactive'
            };
            this.upsertLocalMappingRow(savedRow);
            if (savedRow.active) {
                this.applyLocalActivation(savedRow.developerName, savedRow.objectApiName, savedRow.workspace);
            }

            this.mappingStatusMessage = `Mapping guardado (${result.developerName}). Estado: ${result.deploymentStatus}`;
            this.showToast('Object Mapping', this.mappingStatusMessage, 'success');

            this.mappingForm = {
                developerName: savedRow.developerName,
                objectApiName: savedRow.objectApiName,
                referenceField: savedRow.referenceField,
                amountField: savedRow.amountField,
                currency: savedRow.currency,
                workspace: savedRow.workspace || DEFAULT_CONFIG_NAME,
                active: savedRow.active === true
            };
            this.refreshMappingsInBackground(savedRow.objectApiName);
        } catch (error) {
            this.mappingStatusMessage = 'No se pudo guardar mapping.';
            this.showToast('Object Mapping', this.getErrorMessage(error), 'error');
        } finally {
            this.isMappingBusy = false;
        }
    }

    async handleObjectMappingRefresh() {
        this.isMappingBusy = true;
        this.mappingStatusMessage = '';

        try {
            await Promise.all([
                this.loadObjectMappings(false),
                this.loadObjectMappingObjects(false),
                this.loadMappingWorkspaceOptions(false)
            ]);
            if (this.mappingForm.objectApiName) {
                await this.loadObjectMappingFieldOptions(this.mappingForm.objectApiName, false);
            } else {
                this.mappingReferenceFieldOptions = [];
                this.mappingAmountFieldOptions = [];
            }
            this.mappingStatusMessage = `Mappings actualizados: ${this.mappingRows.length}`;
        } catch (error) {
            this.mappingStatusMessage = 'No se pudo refrescar Object Mapping.';
            this.showToast('Object Mapping', this.getErrorMessage(error), 'error');
        } finally {
            this.isMappingBusy = false;
        }
    }

    async handleMappingRowAction(event) {
        const actionName = event.detail?.action?.name;
        const row = event.detail?.row;
        if (!row || !actionName) {
            return;
        }

        if (actionName === 'edit') {
            this.isMappingBusy = true;
            this.mappingStatusMessage = `Editando mapping: ${row.objectApiName}`;
            try {
                await this.loadObjectMappingFieldOptions(row.objectApiName, false);
                this.mappingForm = {
                    developerName: row.developerName || '',
                    objectApiName: row.objectApiName || '',
                    referenceField: row.referenceField || '',
                    amountField: row.amountField || '',
                    currency: row.currency || '',
                    workspace: row.workspace || DEFAULT_CONFIG_NAME,
                    active: row.active === true
                };
            } catch (error) {
                this.mappingStatusMessage = 'No se pudo cargar mapping para editar.';
                this.showToast('Object Mapping', this.getErrorMessage(error), 'error');
            } finally {
                this.isMappingBusy = false;
            }
            return;
        }

        if (actionName === 'activate' && row.developerName) {
            await this.handleObjectMappingActivate(row.developerName);
            return;
        }

        if (actionName === 'delete' && row.developerName) {
            await this.handleObjectMappingDelete(row.developerName);
        }
    }

    async handleObjectMappingDelete(developerName) {
        this.isMappingBusy = true;
        this.mappingStatusMessage = `Eliminando mapping: ${developerName}...`;

        try {
            const result = await deleteObjectMapping({ developerName });
            const success = result?.success === true;
            if (!success) {
                const message = result?.message || 'No se pudo eliminar el mapping.';
                this.mappingStatusMessage = message;
                this.showToast('Object Mapping', message, 'error');
                return;
            }

            this.mappingStatusMessage = `Mapping eliminado (${developerName}). Estado: ${result.deploymentStatus}`;
            this.showToast('Object Mapping', this.mappingStatusMessage, 'success');

            this.removeLocalMappingRow(developerName);
            if (this.mappingForm.developerName === developerName) {
                const fallbackWorkspace =
                    this.mappingForm.workspace ||
                    (this.mappingWorkspaceOptions.length > 0
                        ? this.mappingWorkspaceOptions[0].value
                        : DEFAULT_CONFIG_NAME);
                this.mappingForm = this.buildNewMappingForm(fallbackWorkspace);
                this.mappingReferenceFieldOptions = [];
                this.mappingAmountFieldOptions = [];
            }
            this.refreshMappingsInBackground();
        } catch (error) {
            this.mappingStatusMessage = 'No se pudo eliminar el mapping.';
            this.showToast('Object Mapping', this.getErrorMessage(error), 'error');
        } finally {
            this.isMappingBusy = false;
        }
    }

    async handleObjectMappingActivate(developerName) {
        this.isMappingBusy = true;
        this.mappingStatusMessage = `Activando mapping: ${developerName}...`;

        try {
            const result = await activateObjectMapping({ developerName });
            const success = result?.success === true;
            if (!success) {
                const message = result?.message || 'No se pudo activar el mapping.';
                this.mappingStatusMessage = message;
                this.showToast('Object Mapping', message, 'error');
                return;
            }

            const activatedRow = this.mappingRows.find((row) => row.developerName === developerName);
            if (activatedRow) {
                this.applyLocalActivation(developerName, activatedRow.objectApiName, activatedRow.workspace);
            }

            if (activatedRow) {
                this.mappingForm = {
                    developerName: activatedRow.developerName || '',
                    objectApiName: activatedRow.objectApiName || '',
                    referenceField: activatedRow.referenceField || '',
                    amountField: activatedRow.amountField || '',
                    currency: activatedRow.currency || '',
                    workspace: activatedRow.workspace || DEFAULT_CONFIG_NAME,
                    active: true
                };
            }

            this.mappingStatusMessage = `Mapping activado (${developerName}). Estado: ${result.deploymentStatus}`;
            this.showToast('Object Mapping', this.mappingStatusMessage, 'success');
            this.refreshMappingsInBackground();
        } catch (error) {
            this.mappingStatusMessage = 'No se pudo activar el mapping.';
            this.showToast('Object Mapping', this.getErrorMessage(error), 'error');
        } finally {
            this.isMappingBusy = false;
        }
    }

    upsertLocalMappingRow(savedRow) {
        this.pendingDeletedDeveloperNames.delete(savedRow.developerName);
        const existingIndex = this.mappingRows.findIndex((row) => row.developerName === savedRow.developerName);
        if (existingIndex === -1) {
            this.mappingRows = [savedRow, ...this.mappingRows];
            return;
        }

        const updatedRows = [...this.mappingRows];
        updatedRows[existingIndex] = {
            ...updatedRows[existingIndex],
            ...savedRow
        };
        this.mappingRows = updatedRows;
    }

    removeLocalMappingRow(developerName) {
        this.pendingDeletedDeveloperNames.add(developerName);
        this.mappingRows = this.mappingRows.filter((row) => row.developerName !== developerName);
    }

    applyLocalActivation(developerName, objectApiName, workspace) {
        const objectKey = this.normalizeMappingKey(objectApiName);
        const workspaceKey = this.normalizeMappingKey(workspace);
        this.mappingRows = this.mappingRows.map((row) => {
            const sameScope =
                this.normalizeMappingKey(row.objectApiName) === objectKey &&
                this.normalizeMappingKey(row.workspace) === workspaceKey;

            if (!sameScope) {
                return row;
            }

            const isSelected = row.developerName === developerName;
            return {
                ...row,
                active: isSelected,
                status: isSelected ? 'Active' : 'Inactive'
            };
        });
    }

    normalizeMappingKey(value) {
        return String(value || '').trim().toLowerCase();
    }

    refreshMappingsInBackground(objectApiName) {
        Promise.all([
            this.loadObjectMappings(false),
            this.loadObjectMappingObjects(false),
            this.loadMappingWorkspaceOptions(false)
        ])
            .then(() => {
                if (objectApiName) {
                    return this.loadObjectMappingFieldOptions(objectApiName, false);
                }
                return null;
            })
            .catch(() => {
                // Silent background sync; user already got immediate visual feedback.
            });
    }

    buildNewMappingForm(workspace = DEFAULT_CONFIG_NAME) {
        return {
            developerName: '',
            objectApiName: '',
            referenceField: '',
            amountField: '',
            currency: '',
            workspace,
            active: false
        };
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

    get mappingWorkspaceFilterOptions() {
        const optionMap = new Map();

        (this.mappingWorkspaceOptions || []).forEach((option) => {
            const value = String(option?.value || '').trim();
            if (value) {
                optionMap.set(value, option?.label || value);
            }
        });

        (this.mappingRows || []).forEach((row) => {
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

    get filteredMappingRows() {
        if (this.mappingWorkspaceFilter === ALL_WORKSPACES_FILTER_VALUE) {
            return this.mappingRows;
        }

        return (this.mappingRows || []).filter((row) => String(row?.workspace || '').trim() === this.mappingWorkspaceFilter);
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
