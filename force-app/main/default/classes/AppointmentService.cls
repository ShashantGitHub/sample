public with sharing class AppointmentService {

    public static void preventDoubleBooking(List<Appointment__c> newList, Map<Id, Appointment__c> oldMap) {
        Set<Id> doctorIds = new Set<Id>();
        Set<Id> slotIds = new Set<Id>();
        Set<Date> dates = new Set<Date>();

        // Collect values from incoming records (only consider attempts to BOOK)
        for (Appointment__c a : newList) {
            if (a == null) continue;
            if (a.Status__c == null) continue;
            // We only validate records that are being set to Booked (or not cancelled/completed)
            if (a.Status__c == 'Cancelled' || a.Status__c == 'Completed') continue;
            if (a.Doctors__c == null || a.Timeslot__c == null || a.Appointment_Date__c == null) continue;

            doctorIds.add(a.Doctors__c);
            slotIds.add(a.Timeslot__c);
            dates.add(a.Appointment_Date__c);
        }

        if (doctorIds.isEmpty()) return;

        // === QUERY DOCTORS ===
        // Use the actual Doctor sObject type in your org. Most orgs use Doctor__c (singular).
        // If your object API name is different, replace Doctor__c below with the correct API name.
        Map<Id, Doctor__c> doctorMap = new Map<Id, Doctor__c>([
            SELECT Id, Name, IsActive__c
            FROM Doctor__c
            WHERE Id IN :doctorIds
        ]);

        // === QUERY EXISTING APPOINTMENTS (only those that are Booked) ===
        List<Appointment__c> existing = [
            SELECT Id, Doctors__c, Timeslot__c, Appointment_Date__c, Status__c
            FROM Appointment__c
            WHERE Doctors__c IN :doctorIds
              AND Timeslot__c IN :slotIds
              AND Appointment_Date__c IN :dates
              AND Status__c = 'Booked'
        ];

        // Build set of keys for already-booked slots
        Set<String> bookedKeys = new Set<String>();
        for (Appointment__c ex : existing) {
            if (ex == null) continue;
            // only consider those with Status = Booked (we already filtered, but keep safe)
            if (ex.Status__c == 'Booked' && ex.Doctors__c != null && ex.Timeslot__c != null && ex.Appointment_Date__c != null) {
                bookedKeys.add(ex.Doctors__c + '|' + ex.Timeslot__c + '|' + String.valueOf(ex.Appointment_Date__c));
            }
        }

        // === VALIDATE INCOMING RECORDS ===
        for (Appointment__c a : newList) {
            if (a == null) continue;

            // Skip if not booking or missing data
            if (a.Status__c == null) continue;
            if (a.Status__c == 'Cancelled' || a.Status__c == 'Completed') continue;
            if (a.Doctors__c == null || a.Timeslot__c == null || a.Appointment_Date__c == null) continue;

            // Check doctor active status first
            Doctor__c docRec = doctorMap.get(a.Doctors__c);
            if (docRec == null) {
                // If doctor not found, block and prompt admin to check data
                a.addError('Doctor record not found. Please check the selected Doctor.');
                continue;
            }
            if (docRec.IsActive__c == false) {
                a.addError('Cannot confirm appointment. Doctor "' + docRec.Name + '" is not active.');
                continue;
            }

            // Now check for double booking for active doctor
            String key = a.Doctors__c + '|' + a.Timeslot__c + '|' + String.valueOf(a.Appointment_Date__c);

            // If an existing booked appointment exists for this key, block the booking.
            // Also handle update cases: if this is the same record being updated from Booked->Booked, it's okay.
            if (bookedKeys.contains(key)) {
                // If updating same record which is already booked, allow it (skip blocking)
                Boolean isUpdatingSameBookedRecord = false;
                if (oldMap != null && a.Id != null && oldMap.containsKey(a.Id)) {
                    Appointment__c oldRec = oldMap.get(a.Id);
                    if (oldRec != null && oldRec.Status__c == 'Booked') {
                        // The record being updated was already Booked before — allow update (not a duplicate)
                        isUpdatingSameBookedRecord = true;
                    }
                }

                if (!isUpdatingSameBookedRecord) {
                    String slotLabel = null;
                    try {
                        // try to get slot label from relationship (null-safe)
                        if (a.Timeslot__r != null && a.Timeslot__r.get('Slot_Time__c') != null) {
                            slotLabel = (String) a.Timeslot__r.get('Slot_Time__c');
                        }
                    } catch (Exception e) {
                        slotLabel = null;
                    }

                    String slotMsg = (slotLabel != null) ? ('Slot: ' + slotLabel + ' - ') : '';
                    a.addError(slotMsg + 'This slot on ' + a.Appointment_Date__c.format() + ' is already booked for this doctor.');
                }
            }
        }
    }
}