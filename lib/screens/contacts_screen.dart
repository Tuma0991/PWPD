// lib/screens/contacts_screen.dart

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/firebase_service.dart';
import '../models/contact_model.dart';

class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final firebase = FirebaseService();
    final userId = firebase.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1565C0),
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.contacts, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text(
              'Emergency Contacts',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddContactDialog(context, firebase, userId),
        backgroundColor: const Color(0xFF1565C0),
        elevation: 4,
        icon: const Icon(Icons.person_add, color: Colors.white),
        label: const Text(
          'Add Contact',
          style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 14),
        ),
      ),
      body: userId.isEmpty
          ? const Center(child: Text('Please log in'))
          : StreamBuilder<List<ContactModel>>(
              stream: firebase.getContacts(userId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final contacts = snapshot.data ?? [];

                if (contacts.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1565C0).withOpacity(0.08),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.contacts,
                            size: 56,
                            color: Color(0xFF1565C0),
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'No contacts yet',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1A2340),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Add family or guardian contacts\nto notify during emergencies.',
                          style: TextStyle(
                              color: Color(0xFF6B7A99), fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }

                final emergency =
                    contacts.where((c) => c.isEmergencyContact).toList();
                final regular =
                    contacts.where((c) => !c.isEmergencyContact).toList();

                return ListView(
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  children: [
                    if (emergency.isNotEmpty) ...[
                      _SectionHeader(
                        title: '🚨 Emergency Contacts',
                        count: emergency.length,
                        color: const Color(0xFFE53935),
                      ),
                      const SizedBox(height: 10),
                      ...emergency.map((c) => _ContactCard(
                            contact: c,
                            onDelete: () =>
                                firebase.deleteContact(userId, c.id),
                            onEdit: () => _showEditDialog(
                                context, firebase, userId, c),
                          )),
                      const SizedBox(height: 20),
                    ],
                    if (regular.isNotEmpty) ...[
                      _SectionHeader(
                        title: 'Other Contacts',
                        count: regular.length,
                        color: const Color(0xFF1565C0),
                      ),
                      const SizedBox(height: 10),
                      ...regular.map((c) => _ContactCard(
                            contact: c,
                            onDelete: () =>
                                firebase.deleteContact(userId, c.id),
                            onEdit: () => _showEditDialog(
                                context, firebase, userId, c),
                          )),
                    ],
                  ],
                );
              },
            ),
    );
  }

  void _showAddContactDialog(
      BuildContext context, FirebaseService firebase, String userId) {
    _showContactDialog(context, firebase, userId, null);
  }

  void _showEditDialog(BuildContext context, FirebaseService firebase,
      String userId, ContactModel contact) {
    _showContactDialog(context, firebase, userId, contact);
  }

  void _showContactDialog(BuildContext context, FirebaseService firebase,
      String userId, ContactModel? existing) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final relCtrl =
        TextEditingController(text: existing?.relationship ?? '');
    bool isEmergency = existing?.isEmergencyContact ?? false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
          padding: EdgeInsets.fromLTRB(
              24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDDE3F0),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1565C0).withOpacity(0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.person_add,
                        color: Color(0xFF1565C0), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    existing == null ? 'Add Contact' : 'Edit Contact',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A2340),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _SheetTextField(
                controller: nameCtrl,
                label: 'Full Name',
                icon: Icons.person_outline,
              ),
              const SizedBox(height: 12),
              _SheetTextField(
                controller: phoneCtrl,
                label: 'Phone Number',
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              _SheetTextField(
                controller: relCtrl,
                label: 'Relationship (e.g. Mother, Father)',
                icon: Icons.family_restroom,
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: isEmergency
                      ? const Color(0xFFFFEBEE)
                      : const Color(0xFFF7F9FF),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isEmergency
                        ? const Color(0xFFE53935).withOpacity(0.3)
                        : const Color(0xFFDDE3F0),
                  ),
                ),
                child: SwitchListTile(
                  value: isEmergency,
                  onChanged: (v) => setModalState(() => isEmergency = v),
                  title: Text(
                    'Emergency Contact',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: isEmergency
                          ? const Color(0xFFE53935)
                          : const Color(0xFF1A2340),
                      fontSize: 14,
                    ),
                  ),
                  subtitle: const Text(
                    'Will be notified first during alerts',
                    style: TextStyle(fontSize: 12, color: Color(0xFF6B7A99)),
                  ),
                  activeColor: const Color(0xFFE53935),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: () async {
                    if (nameCtrl.text.isEmpty || phoneCtrl.text.isEmpty) {
                      return;
                    }
                    final contact = ContactModel(
                      id: existing?.id ?? '',
                      name: nameCtrl.text.trim(),
                      phone: phoneCtrl.text.trim(),
                      relationship: relCtrl.text.trim(),
                      isEmergencyContact: isEmergency,
                    );
                    if (existing == null) {
                      await firebase.addContact(userId, contact);
                    } else {
                      await firebase.updateContact(userId, existing.id, contact);
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(
                    existing == null ? 'Add Contact' : 'Save Changes',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;

  const _SheetTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(
          fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF1A2340)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            const TextStyle(color: Color(0xFF6B7A99), fontSize: 13),
        prefixIcon: Icon(icon, color: const Color(0xFF1565C0), size: 20),
        filled: true,
        fillColor: const Color(0xFFF7F9FF),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: Color(0xFFDDE3F0), width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: Color(0xFF1565C0), width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final Color color;
  const _SectionHeader(
      {required this.title, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _ContactCard extends StatelessWidget {
  final ContactModel contact;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const _ContactCard({
    required this.contact,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final isEmergency = contact.isEmergencyContact;
    final color = isEmergency
        ? const Color(0xFFE53935)
        : const Color(0xFF1565C0);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.15), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  color.withOpacity(0.15),
                  color.withOpacity(0.08),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              border: Border.all(color: color.withOpacity(0.25), width: 1.5),
            ),
            child: Center(
              child: Text(
                contact.name.isNotEmpty ? contact.name[0].toUpperCase() : '?',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        contact.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A2340),
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isEmergency) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE53935).withOpacity(0.10),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'SOS',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFE53935),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  contact.phone,
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF6B7A99)),
                ),
                if (contact.relationship.isNotEmpty)
                  Text(
                    contact.relationship,
                    style: TextStyle(
                      fontSize: 11,
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          // Call button
          Container(
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF2E7D32).withOpacity(0.10),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.phone,
                  color: Color(0xFF2E7D32), size: 19),
              onPressed: () async {
                final uri = Uri.parse('tel:${contact.phone}');
                if (await canLaunchUrl(uri)) launchUrl(uri);
              },
              constraints: const BoxConstraints(
                minWidth: 36,
                minHeight: 36,
              ),
              padding: const EdgeInsets.all(8),
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert,
                color: Color(0xFF9EA8C2), size: 20),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            onSelected: (v) {
              if (v == 'edit') onEdit();
              if (v == 'delete') {
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                    title: const Text('Delete Contact',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    content: Text(
                        'Remove ${contact.name} from your contacts?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel')),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE53935),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () {
                          onDelete();
                          Navigator.pop(context);
                        },
                        child: const Text('Delete',
                            style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                );
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                  value: 'edit',
                  child: Row(children: [
                    Icon(Icons.edit_outlined,
                        size: 18, color: Color(0xFF1565C0)),
                    SizedBox(width: 10),
                    Text('Edit'),
                  ])),
              const PopupMenuItem(
                  value: 'delete',
                  child: Row(children: [
                    Icon(Icons.delete_outline,
                        size: 18, color: Color(0xFFE53935)),
                    SizedBox(width: 10),
                    Text('Delete',
                        style: TextStyle(color: Color(0xFFE53935))),
                  ])),
            ],
          ),
        ],
      ),
    );
  }
}