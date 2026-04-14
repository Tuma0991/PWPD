// lib/models/contact_model.dart

class ContactModel {
  final String id;
  final String name;
  final String phone;
  final String relationship;
  final bool isEmergencyContact;

  ContactModel({
    required this.id,
    required this.name,
    required this.phone,
    required this.relationship,
    this.isEmergencyContact = false,
  });

  factory ContactModel.fromMap(String id, Map<String, dynamic> map) {
    return ContactModel(
      id: id,
      name: map['name'] ?? '',
      phone: map['phone'] ?? '',
      relationship: map['relationship'] ?? '',
      isEmergencyContact: map['isEmergencyContact'] ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'phone': phone,
        'relationship': relationship,
        'isEmergencyContact': isEmergencyContact,
      };

  ContactModel copyWith({
    String? name,
    String? phone,
    String? relationship,
    bool? isEmergencyContact,
  }) {
    return ContactModel(
      id: id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      relationship: relationship ?? this.relationship,
      isEmergencyContact: isEmergencyContact ?? this.isEmergencyContact,
    );
  }
}
