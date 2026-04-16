import { LightningElement } from 'lwc';

export default class GetnetPaymentApp extends LightningElement {
    handleMetadataWorkspaceChanged() {
        const quickPaymentComponent = this.template.querySelector('c-getnet-quick-payment');
        if (quickPaymentComponent && typeof quickPaymentComponent.refreshWorkspaceOptions === 'function') {
            quickPaymentComponent.refreshWorkspaceOptions();
        }
    }
}
