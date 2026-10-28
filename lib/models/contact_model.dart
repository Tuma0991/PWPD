// lib/models/contact_model.dart

/// Carrier-to-SMS-gateway mapping used for free email-to-SMS delivery.
const Map<String, String> carrierSmsGateways = {
  'Globe (PH)': 'txt.globe.com.ph',
  'Smart (PH)': 'isms.smart.com.ph',
  'Sun (PH)': 'suncellular.com.ph',
  'DITO (PH)': 'ditosms.com',
  'Verizon': 'vtext.com',
  'AT&T': 'txt.att.net',
  'T-Mobile': 'tmomail.net',
  'Sprint': 'messaging.sprintpcs.com',
};

class ContactModel {
  final String id;
  final String name;
  final String phone;
  final String relationship;
  final String carrier;
  final bool isEmergencyContact;

  ContactModel({
    required this.id,
    required this.name,
    required this.phone,
    required this.relationship,
    this.carrier = '',
    this.isEmergencyContact = false,
  });

  factory ContactModel.fromMap(String id, Map<String, dynamic> map) {
    return ContactModel(
      id: id,
      name: map['name'] ?? '',
      phone: map['phone'] ?? '',
      relationship: map['relationship'] ?? '',
      carrier: map['carrier'] ?? '',
      isEmergencyContact: map['isEmergencyContact'] ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'phone': phone,
        'relationship': relationship,
        'carrier': carrier,
        'isEmergencyContact': isEmergencyContact,
      };

  ContactModel copyWith({
    String? name,
    String? phone,
    String? relationship,
    String? carrier,
    bool? isEmergencyContact,
  }) {
    return ContactModel(
      id: id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      relationship: relationship ?? this.relationship,
      carrier: carrier ?? this.carrier,
      isEmergencyContact: isEmergencyContact ?? this.isEmergencyContact,
    );
  }
}
