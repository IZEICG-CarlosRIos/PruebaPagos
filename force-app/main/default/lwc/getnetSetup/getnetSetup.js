import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getAuthorizationConfig from '@salesforce/apex/GetNetPaymentUiFacade.getAuthorizationConfig';
import saveAuthorizationConfigDirect from '@salesforce/apex/GetNetPaymentUiFacade.saveAuthorizationConfigDirect';
import getWorkspaceOptions from '@salesforce/apex/GetNetPaymentUiFacade.getWorkspaceOptions';

const AUTH_REQUIRED_FIELDS = ['companyId', 'branchId', 'user', 'password', 'encryptionKey', 'data0'];
const ENCRYPTION_KEY_REGEX = /^[A-Fa-f0-9]{32}$/;
const WORKSPACE_NAME_REGEX = /^[A-Za-z][A-Za-z0-9_]*$/;
const DEFAULT_CONFIG_NAME = 'ConfiguracionPrueba';
const NEW_WORKSPACE_OPTION_VALUE = '__NEW_WORKSPACE__';

export default class GetnetSetup extends LightningElement {
    authProgressStep = 'configuration';
    authorizationConfigName = DEFAULT_CONFIG_NAME;
    authorizationWorkspaceSelection = DEFAULT_CONFIG_NAME;
    authorizationNewWorkspace = '';
    authorizationWorkspaceOptions = [];
    authorizationCachedConfigs = {};
    authStatusMessage = 'Cargando configuracion...';
    isAuthorizationBusy = false;

    authForm = {
        companyId: '',
        branchId: '',
        user: '',
        password: '',
        encryptionKey: '',
        data0: ''
    };

    connectedCallback() {
        this.initializeAuthorizationSetup();
    }

    getEmptyAuthForm() {
        return {
            companyId: '',
            branchId: '',
            user: '',
            password: '',
            encryptionKey: '',
            data0: ''
        };
    }

    async initializeAuthorizationSetup() {
        this.isAuthorizationBusy = true;
        this.authProgressStep = 'configuration';
        this.authStatusMessage = 'Cargando workspaces...';

        try {
            await this.loadAuthorizationWorkspaceOptions(false);
            this.ensureAuthorizationWorkspaceSelection();
            if (this.hasResolvedAuthorizationConfigName()) {
                await this.loadAuthorizationConfig(false);
            } else {
                this.authForm = this.getEmptyAuthForm();
                this.authStatusMessage = 'Selecciona o crea un workspace para configurar credenciales.';
            }
        } catch (error) {
            this.authStatusMessage = 'No se pudo inicializar Authorization.';
            this.showToast('Authorization', this.getErrorMessage(error), 'error');
        } finally {
            this.isAuthorizationBusy = false;
        }
    }

    hasResolvedAuthorizationConfigName() {
        return String(this.getResolvedAuthorizationConfigName() || '').trim() !== '';
    }

    getResolvedAuthorizationConfigName() {
        if (this.authorizationWorkspaceSelection === NEW_WORKSPACE_OPTION_VALUE) {
            return String(this.authorizationNewWorkspace || '').trim();
        }

        const selectedWorkspace = String(this.authorizationWorkspaceSelection || '').trim();
        if (selectedWorkspace) {
            return selectedWorkspace;
        }

        return String(this.authorizationConfigName || '').trim();
    }

    ensureAuthorizationWorkspaceSelection() {
        if (this.authorizationWorkspaceOptions.length === 0) {
            this.authorizationConfigName = DEFAULT_CONFIG_NAME;
            this.authorizationWorkspaceSelection = DEFAULT_CONFIG_NAME;
            return;
        }

        let desiredWorkspace = String(this.authorizationConfigName || '').trim();
        if (!desiredWorkspace) {
            desiredWorkspace = String(this.authorizationWorkspaceSelection || '').trim();
        }

        const hasDesiredWorkspace = this.authorizationWorkspaceOptions.some((option) => option.value === desiredWorkspace);
        if (!hasDesiredWorkspace) {
            desiredWorkspace = this.authorizationWorkspaceOptions[0].value;
        }

        this.authorizationConfigName = desiredWorkspace;
        this.authorizationWorkspaceSelection = desiredWorkspace;
    }

    upsertAuthorizationWorkspaceOption(workspaceName) {
        const normalizedWorkspace = String(workspaceName || '').trim();
        if (!normalizedWorkspace) {
            return;
        }

        const alreadyExists = this.authorizationWorkspaceOptions.some((option) => option.value === normalizedWorkspace);
        if (alreadyExists) {
            return;
        }

        this.authorizationWorkspaceOptions = [
            ...this.authorizationWorkspaceOptions,
            { label: normalizedWorkspace, value: normalizedWorkspace }
        ].sort((left, right) => String(left.value || '').localeCompare(String(right.value || '')));
    }

    async loadAuthorizationWorkspaceOptions(manageState = true) {
        if (manageState) {
            this.isAuthorizationBusy = true;
        }

        try {
            const options = await getWorkspaceOptions({});
            const fetchedOptions = (options || []).map((option) => ({
                label: option.label,
                value: option.value
            }));

            const mergedByValue = new Map();
            [...this.authorizationWorkspaceOptions, ...fetchedOptions].forEach((option) => {
                const value = String(option?.value || '').trim();
                if (!value || mergedByValue.has(value)) {
                    return;
                }
                mergedByValue.set(value, {
                    label: String(option?.label || value),
                    value
                });
            });

            const mergedOptions = [...mergedByValue.values()].sort((left, right) =>
                String(left.value || '').localeCompare(String(right.value || ''))
            );

            this.authorizationWorkspaceOptions = mergedOptions.length > 0
                ? mergedOptions
                : [{ label: DEFAULT_CONFIG_NAME, value: DEFAULT_CONFIG_NAME }];
        } catch (error) {
            this.authorizationWorkspaceOptions = [];
            if (manageState) {
                this.showToast('Authorization', this.getErrorMessage(error), 'error');
            }
            throw error;
        } finally {
            if (manageState) {
                this.isAuthorizationBusy = false;
            }
        }
    }

    handleAuthorizationWorkspaceChange(event) {
        const selectedWorkspace = event.detail?.value;
        if (!selectedWorkspace || selectedWorkspace === this.authorizationWorkspaceSelection) {
            return;
        }

        if (selectedWorkspace === NEW_WORKSPACE_OPTION_VALUE) {
            this.authorizationWorkspaceSelection = NEW_WORKSPACE_OPTION_VALUE;
            this.authorizationConfigName = '';
            this.authorizationNewWorkspace = '';
            this.authForm = this.getEmptyAuthForm();
            this.authProgressStep = 'configuration';
            this.authStatusMessage = 'Captura un nombre de workspace nuevo y completa credenciales.';
            return;
        }

        this.authorizationWorkspaceSelection = selectedWorkspace;
        this.authorizationConfigName = selectedWorkspace;
        this.authorizationNewWorkspace = '';
        this.loadAuthorizationConfig();
    }

    handleAuthorizationNewWorkspaceChange(event) {
        this.authorizationNewWorkspace = event.target?.value ?? '';
        this.authorizationConfigName = String(this.authorizationNewWorkspace || '').trim();
        this.authProgressStep = 'configuration';
    }

    handleAuthChange(event) {
        const fieldName = event.target?.name;
        if (!fieldName) {
            return;
        }

        const value = event.target?.value ?? '';
        this.authForm = {
            ...this.authForm,
            [fieldName]: value
        };
    }

    buildAuthFormFromResponse(response) {
        return {
            companyId: response?.companyId || '',
            branchId: response?.branchId || '',
            user: response?.user || '',
            password: response?.password || '',
            encryptionKey: response?.encryptionKey || '',
            data0: response?.data0 || ''
        };
    }

    hasAuthFormData(form) {
        return AUTH_REQUIRED_FIELDS.some((fieldName) => String(form?.[fieldName] || '').trim() !== '');
    }

    async loadAuthorizationConfig(manageState = true) {
        const targetConfigName = String(this.authorizationConfigName || '').trim();
        if (!targetConfigName) {
            this.authForm = this.getEmptyAuthForm();
            this.authStatusMessage = 'Workspace es obligatorio.';
            return;
        }

        if (manageState) {
            this.isAuthorizationBusy = true;
        }
        this.authProgressStep = 'configuration';
        this.authStatusMessage = `Leyendo configuracion actual (${targetConfigName})...`;

        try {
            const response = await getAuthorizationConfig({ configName: targetConfigName });
            this.authorizationConfigName = response?.configName || targetConfigName;
            if (this.authorizationWorkspaceSelection !== NEW_WORKSPACE_OPTION_VALUE) {
                this.authorizationWorkspaceSelection = this.authorizationConfigName;
            }

            const serverForm = this.buildAuthFormFromResponse(response);
            const hasServerData = this.hasAuthFormData(serverForm);
            if (hasServerData) {
                this.authForm = serverForm;
                this.authorizationCachedConfigs = {
                    ...this.authorizationCachedConfigs,
                    [this.authorizationConfigName]: { ...serverForm }
                };
                this.authStatusMessage = `Configuracion cargada: ${this.authorizationConfigName}`;
            } else {
                const cachedForm = this.authorizationCachedConfigs[this.authorizationConfigName];
                if (cachedForm) {
                    this.authForm = { ...cachedForm };
                    this.authStatusMessage =
                        `Configuracion ${this.authorizationConfigName} en despliegue. Mostrando valores guardados localmente.`;
                } else {
                    this.authForm = serverForm;
                    this.authStatusMessage = `Workspace ${this.authorizationConfigName} sin configuracion guardada.`;
                }
            }

            this.authProgressStep = 'validation';
        } catch (error) {
            this.authStatusMessage = 'No se pudo cargar la configuracion.';
            this.showToast('Authorization', this.getErrorMessage(error), 'error');
        } finally {
            if (manageState) {
                this.isAuthorizationBusy = false;
            }
        }
    }

    async handleAuthorizationSave() {
        this.isAuthorizationBusy = true;
        this.authProgressStep = 'validation';
        this.authStatusMessage = 'Validando y guardando configuracion...';

        try {
            const resolvedConfigName = this.getResolvedAuthorizationConfigName();
            if (!String(resolvedConfigName || '').trim()) {
                this.authStatusMessage = 'Workspace es obligatorio.';
                this.showToast('Authorization', this.authStatusMessage, 'error');
                return;
            }

            if (
                this.authorizationWorkspaceSelection === NEW_WORKSPACE_OPTION_VALUE &&
                !WORKSPACE_NAME_REGEX.test(resolvedConfigName)
            ) {
                this.authStatusMessage =
                    'Nuevo Workspace invalido. Usa letras, numeros y "_" e inicia con letra.';
                this.showToast('Authorization', this.authStatusMessage, 'error');
                return;
            }

            const authPayload = { ...this.authForm };
            const validationError = this.validateAuthorizationForm(authPayload);
            if (validationError) {
                this.authStatusMessage = validationError;
                this.showToast('Authorization', validationError, 'error');
                return;
            }

            const result = await saveAuthorizationConfigDirect({
                configName: resolvedConfigName,
                companyId: authPayload.companyId,
                branchId: authPayload.branchId,
                user: authPayload.user,
                password: authPayload.password,
                encryptionKey: authPayload.encryptionKey,
                data0: authPayload.data0
            });
            const success = result?.success === true;
            if (success) {
                const savedConfigName = result?.configName || resolvedConfigName;
                this.authorizationConfigName = savedConfigName;
                this.authorizationWorkspaceSelection = savedConfigName;
                this.authorizationNewWorkspace = '';
                this.authorizationCachedConfigs = {
                    ...this.authorizationCachedConfigs,
                    [savedConfigName]: { ...authPayload }
                };
                this.upsertAuthorizationWorkspaceOption(savedConfigName);
                await this.loadAuthorizationWorkspaceOptions(false);
                this.authForm = { ...authPayload };
            }

            this.authProgressStep = success ? 'connected' : 'validation';
            this.authStatusMessage = success
                ? `Configuracion guardada (${this.authorizationConfigName}). Estado: ${result.deploymentStatus}`
                : result?.message || 'No se pudo guardar la configuracion.';

            this.showToast('Authorization', this.authStatusMessage, success ? 'success' : 'error');
        } catch (error) {
            this.authProgressStep = 'validation';
            this.authStatusMessage = 'No se pudo guardar la configuracion.';
            this.showToast('Authorization', this.getErrorMessage(error), 'error');
        } finally {
            this.isAuthorizationBusy = false;
        }
    }

    validateAuthorizationForm(form) {
        const values = form || {};
        if (!String(values.companyId || '').trim()) {
            return 'Company ID es obligatorio.';
        }
        if (!String(values.branchId || '').trim()) {
            return 'Branch ID es obligatorio.';
        }
        if (!String(values.user || '').trim()) {
            return 'User es obligatorio.';
        }
        if (!String(values.password || '').trim()) {
            return 'Password es obligatorio.';
        }
        if (!String(values.encryptionKey || '').trim()) {
            return 'Encryption Key es obligatorio.';
        }
        if (!this.isValidEncryptionKey(values.encryptionKey)) {
            return 'Encryption Key debe ser hexadecimal de 32 caracteres.';
        }
        if (!String(values.data0 || '').trim()) {
            return 'Data0 es obligatorio.';
        }

        return null;
    }

    isValidEncryptionKey(value) {
        const normalized = String(value || '').trim();
        return ENCRYPTION_KEY_REGEX.test(normalized);
    }

    isFieldCompleted(fieldName) {
        const value = String(this.authForm?.[fieldName] || '').trim();
        if (!value) {
            return false;
        }
        if (fieldName === 'encryptionKey') {
            return this.isValidEncryptionKey(value);
        }
        return true;
    }

    get completedFieldCount() {
        return AUTH_REQUIRED_FIELDS.reduce((acc, fieldName) => acc + (this.isFieldCompleted(fieldName) ? 1 : 0), 0);
    }

    get completionPercentage() {
        return Math.round((this.completedFieldCount / AUTH_REQUIRED_FIELDS.length) * 100);
    }

    get isSaveDisabled() {
        const resolvedConfigName = this.getResolvedAuthorizationConfigName();
        const isNewWorkspaceValid = !this.isNewAuthorizationWorkspaceSelected || WORKSPACE_NAME_REGEX.test(resolvedConfigName);
        return (
            this.isAuthorizationBusy ||
            !String(resolvedConfigName || '').trim() ||
            !isNewWorkspaceValid ||
            this.completionPercentage < 100
        );
    }

    get progressRingStyle() {
        const filledDegrees = Math.round((this.completionPercentage / 100) * 360);
        return `background: conic-gradient(#2e844a ${filledDegrees}deg, #d8dde6 ${filledDegrees}deg 360deg)`;
    }

    get progressSummaryMessage() {
        if (this.isAuthorizationBusy) {
            return this.authStatusMessage;
        }

        if (this.completionPercentage === 100) {
            return 'Formulario completo. Save habilitado.';
        }

        if (!String(this.getResolvedAuthorizationConfigName() || '').trim()) {
            return 'Selecciona o crea un workspace para habilitar Save.';
        }

        if (
            this.isNewAuthorizationWorkspaceSelected &&
            String(this.authorizationNewWorkspace || '').trim() &&
            !WORKSPACE_NAME_REGEX.test(this.authorizationNewWorkspace.trim())
        ) {
            return 'Nuevo Workspace invalido. Usa letras, numeros y "_" e inicia con letra.';
        }

        const remaining = AUTH_REQUIRED_FIELDS.length - this.completedFieldCount;
        if (String(this.authForm.encryptionKey || '').trim() && !this.isValidEncryptionKey(this.authForm.encryptionKey)) {
            return 'Encryption Key debe ser hexadecimal de 32 caracteres.';
        }

        return `Completa ${remaining} campo(s) obligatorio(s) para habilitar Save.`;
    }

    get progressSummaryClass() {
        if (!this.isAuthorizationBusy && this.completionPercentage === 100) {
            return 'panel-hint panel-hint-centered';
        }
        return 'panel-hint';
    }

    get authorizationWorkspaceComboboxOptions() {
        return [
            ...this.authorizationWorkspaceOptions,
            { label: 'Nuevo workspace...', value: NEW_WORKSPACE_OPTION_VALUE }
        ];
    }

    get isNewAuthorizationWorkspaceSelected() {
        return this.authorizationWorkspaceSelection === NEW_WORKSPACE_OPTION_VALUE;
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
