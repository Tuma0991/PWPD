class DeviceSettingsModel {
  final String name;
  final String photoBase64;

  const DeviceSettingsModel({this.name = '', this.photoBase64 = ''});

  factory DeviceSettingsModel.fromMap(Map<String, dynamic> map) {
    return DeviceSettingsModel(
      name: (map['name'] ?? '') as String,
      photoBase64: (map['photoBase64'] ?? '') as String,
    );
  }

  Map<String, dynamic> toMap() => {'name': name, 'photoBase64': photoBase64};
}
