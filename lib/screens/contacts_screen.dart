// lib/screens/contacts_screen.dart

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/firebase_service.dart';
import '../models/contact_model.dart';
import '../theme.dart';

class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final firebase = FirebaseService();
    final userId = firebase.currentUser?.uid ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Contacts'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddContactDialog(context, firebase, userId),
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.person_add, color: Colors.white),
        label: const Text('Add Contact',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
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
                        Icon(Icons.contacts,
                            size: 64,
                            color: AppTheme.textSecondary.withOpacity(0.4)),
                        const SizedBox(height: 16),
                        const Text(
                          'No contacts yet',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Add family or guardian contacts\nto notify during emergencies.',
                          style: TextStyle(
                              color: AppTheme.textSecondary, fontSize: 13),
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
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                  children: [
                    if (emergency.isNotEmpty) ...[
                      const _SectionHeader(
                          title: '🚨 Emergency Contacts',
                          color: AppTheme.danger),
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
                      const _SectionHeader(
                          title: 'Other Contacts',
                          color: AppTheme.primary),
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
            color: AppTheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                existing == null ? 'Add Contact' : 'Edit Contact',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Full Name',
                  prefixIcon: Icon(Icons.person_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: relCtrl,
                decoration: const InputDecoration(
                  labelText: 'Relationship (e.g. Mother, Father)',
                  prefixIcon: Icon(Icons.family_restroom),
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                value: isEmergency,
                onChanged: (v) => setModalState(() => isEmergency = v),
                title: const Text(
                  'Emergency Contact',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text('Will be notified first during alerts'),
                activeThumbColor: AppTheme.danger,
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
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
                child: Text(existing == null ? 'Add Contact' : 'Save Changes'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Color color;
  const _SectionHeader({required this.title, required this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w800,
        color: color,
      ),
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
    final color = isEmergency ? AppTheme.danger : AppTheme.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
        boxShadow: const [
          BoxShadow(
            color: AppTheme.cardShadow,
            blurRadius: 6,
            offset: Offset(0, 2),
          )
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withOpacity(0.12),
            radius: 22,
            child: Text(
              contact.name.isNotEmpty ? contact.name[0].toUpperCase() : '?',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  contact.phone,
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary),
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
          IconButton(
            icon: const Icon(Icons.phone, color: AppTheme.success, size: 20),
            onPressed: () async {
              final uri = Uri.parse('tel:${contact.phone}');
              if (await canLaunchUrl(uri)) launchUrl(uri);
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert,
                color: AppTheme.textSecondary, size: 20),
            onSelected: (v) {
              if (v == 'edit') onEdit();
              if (v == 'delete') {
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Delete Contact'),
                    content: Text(
                        'Remove ${contact.name} from your contacts?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel')),
                      TextButton(
                        onPressed: () {
                          onDelete();
                          Navigator.pop(context);
                        },
                        child: const Text('Delete',
                            style: TextStyle(color: AppTheme.danger)),
                      ),
                    ],
                  ),
                );
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              const PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete',
                      style: TextStyle(color: AppTheme.danger))),
            ],
          ),
        ],
      ),
    );
  }
}
