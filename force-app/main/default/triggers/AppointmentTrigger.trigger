trigger AppointmentTrigger on Appointment__c (before insert, before update) {
    if (Trigger.isBefore && (Trigger.isInsert || Trigger.isUpdate)) {
        AppointmentService.preventDoubleBooking(Trigger.new, Trigger.oldMap);
    }
}