public with sharing class PaymentLinkFlowActions {

    public class Input {
        @InvocableVariable(required=true)
        public Id paymentLinkId;
    }

    public class Output {
        @InvocableVariable
        public Id paymentLinkId;

        @InvocableVariable
        public String paymentUrl;

        @InvocableVariable
        public String status;

        @InvocableVariable
        public String message;
    }

    @InvocableMethod(label='Generate Payment Link' description='Genera liga PagosOnline y regresa URL/Status')
    public static List<Output> generate(List<Input> inputs) {
        List<Output> results = new List<Output>();

        for (Input i : inputs) {
            Output o = new Output();
            o.paymentLinkId = i.paymentLinkId;

            try {
                Payment_Link__c updated = PaymentLinkService.generateLink(i.paymentLinkId);
                o.paymentUrl = updated.Payment_URL__c;
                o.status = updated.Status__c;
                o.message = 'OK';
            } catch (Exception e) {
                o.status = 'Error';
                o.message = e.getMessage();
            }

            results.add(o);
        }

        return results;
    }
}