import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/bn.dart';
import '../../core/widgets.dart';
import '../../services/app_state.dart';
import '../../services/api.dart';
import '../../services/auth_service.dart';
import '../../services/images.dart';
import '../../services/location_service.dart';

class OwnerRegisterScreen extends StatefulWidget {
  const OwnerRegisterScreen({super.key});
  @override
  State<OwnerRegisterScreen> createState() => _OwnerRegisterScreenState();
}

class _OwnerRegisterScreenState extends State<OwnerRegisterScreen> {
  final _key = GlobalKey<FormState>();
  final _name = TextEditingController(), _addr = TextEditingController(), _phone = TextEditingController(), _lic = TextEditingController();
  String? _licImage;
  double? _lat, _lng;
  bool _busy = false;

  String? _req(String? v) => (v ?? '').trim().isEmpty ? 'এটি লিখতে হবে' : null;

  Future<void> _submit() async {
    if (!_key.currentState!.validate()) return;
    if (_licImage == null) { context.toast('লাইসেন্সের ছবি দিন'); return; }
    setState(() => _busy = true);
    try {
      // Kept small (<=700 KB); the server stores it privately for admin verification only.
      final bytes = await File(_licImage!).readAsBytes();
      if (bytes.length > 700 * 1024) throw StateError('ছবিটি বড়, আরেকটি ছোট ছবি দিন');
      await Api.instance.post('/pharmacy', {
        'name': _name.text.trim(), 'address': _addr.text.trim(),
        'phone': en(_phone.text.trim()), 'licenseNo': en(_lic.text.trim()),
        'licenseImage': base64Encode(bytes),
        if (_lat != null) 'lat': _lat,
        if (_lng != null) 'lng': _lng,
      });
      if (mounted) await context.read<AppState>().setupDone();
    } catch (e) {
      if (mounted) context.toast('পাঠানো যায়নি: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Form(
        key: _key,
        child: FormPage(
          title: 'দোকানের তথ্য',
          action: PrimaryButton('যাচাইয়ের জন্য পাঠান', busy: _busy, onTap: _submit),
          children: [
            Field('ফার্মেসির নাম', controller: _name, icon: Icons.storefront, validator: _req),
            Field('ঠিকানা', controller: _addr, icon: Icons.location_on, validator: _req),
            OutlineButton2(_lat == null ? 'দোকানে বসে লোকেশন নিন (কাছের গ্রাহক খুঁজে পাবে)' : 'লোকেশন নেওয়া হয়েছে ✓', icon: Icons.my_location, onTap: () async {
              try {
                final p = await LocationService.current();
                setState(() { _lat = p.lat; _lng = p.lng; });
              } catch (e) {
                if (context.mounted) context.toast('$e');
              }
            }),
            const SizedBox(height: 12),
            Field('মোবাইল নম্বর', controller: _phone, icon: Icons.call, keyboard: TextInputType.phone, validator: _req),
            Field('ড্রাগ লাইসেন্স নম্বর', controller: _lic, icon: Icons.badge, validator: _req),
            GestureDetector(
              onTap: () async { final f = await pickImage(camera: false, maxWidth: 1000, quality: 60); if (f != null) setState(() => _licImage = f); },
              child: Container(
                height: 130,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: context.pal.soft, borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: context.pal.border, width: 2),
                  image: _licImage == null ? null : DecorationImage(image: FileImage(File(_licImage!)), fit: BoxFit.cover),
                ),
                child: _licImage == null
                    ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.upload_file, size: 32, color: context.pal.primaryDark),
                        Text('লাইসেন্সের ছবি দিন', style: TextStyle(color: context.pal.primaryDark, fontWeight: FontWeight.w500)),
                      ])
                    : null,
              ),
            ),
            Card2(
              color: const Color(0xFFFFF0D1),
              child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.schedule, color: Color(0xFFA86A08)), SizedBox(width: 10),
                Expanded(child: Text('যাচাইয়ের পর ১-২ দিনের মধ্যে আপনার দোকান লাইভ হবে।', style: TextStyle(height: 1.5, color: Color(0xFF6B4305)))),
              ]),
            ),
            const SizedBox(height: 10),
            TextButton(onPressed: () => context.read<AppState>().switchRole(UserRole.patient), child: const Text('ফিরে যান (আমার স্বাস্থ্য-অ্যাপে)')),
            TextButton(onPressed: () => context.read<AppState>().signOut(), child: const Text('লগআউট')),
          ],
        ),
      );
}
