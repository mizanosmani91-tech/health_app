import 'package:flutter/material.dart';
import 'theme.dart';

class PaletteScope extends InheritedWidget {
  final Palette palette;
  const PaletteScope({super.key, required this.palette, required super.child});
  static Palette of(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<PaletteScope>()?.palette ??
      Palette.patient;
  @override
  bool updateShouldNotify(PaletteScope old) => old.palette != palette;
}

extension Ctx on BuildContext {
  Palette get pal => PaletteScope.of(this);
  void toast(String msg) => ScaffoldMessenger.of(this)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
  Future<T?> push<T>(Widget page) => Navigator.of(this)
      .push<T>(MaterialPageRoute(builder: (_) => PaletteScope(palette: pal, child: page)));
}

class Card2 extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final VoidCallback? onTap;
  final EdgeInsets margin;
  const Card2({super.key, required this.child, this.padding = const EdgeInsets.all(14),
      this.color, this.onTap, this.margin = EdgeInsets.zero});
  @override
  Widget build(BuildContext context) => Padding(
        padding: margin,
        child: Material(
          color: color ?? Colors.white,
          borderRadius: BorderRadius.circular(20),
          elevation: color == null ? 1.5 : 0,
          shadowColor: context.pal.primaryDark.withValues(alpha: .15),
          child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: onTap,
              child: Padding(padding: padding, child: child)),
        ),
      );
}

class IconTile extends StatelessWidget {
  final IconData icon;
  final Tint tint;
  final double size;
  final bool round;
  const IconTile(this.icon, this.tint, {super.key, this.size = 42, this.round = false});
  @override
  Widget build(BuildContext context) => Container(
        width: size, height: size,
        decoration: BoxDecoration(
            color: tint.bg,
            borderRadius: BorderRadius.circular(round ? size : size / 3)),
        child: Icon(icon, color: tint.fg, size: size * .52),
      );
}

class PrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool busy;
  final Color? color;
  const PrimaryButton(this.label, {super.key, this.icon, this.onTap, this.busy = false, this.color});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Opacity(
      opacity: onTap == null ? .5 : 1,
      child: Material(
        borderRadius: BorderRadius.circular(17),
        child: Ink(
          decoration: BoxDecoration(
              gradient: color == null ? p.gradient : null,
              color: color,
              borderRadius: BorderRadius.circular(17),
              boxShadow: [BoxShadow(color: p.primary.withValues(alpha: .3), blurRadius: 16, offset: const Offset(0, 8))]),
          child: InkWell(
            borderRadius: BorderRadius.circular(17),
            onTap: busy ? null : onTap,
            child: SizedBox(
              height: 54,
              child: Center(
                child: busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        if (icon != null) ...[Icon(icon, color: Colors.white), const SizedBox(width: 8)],
                        Text(label, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
                      ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OutlineButton2 extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final Color? fg, bg;
  const OutlineButton2(this.label, {super.key, this.icon, this.onTap, this.fg, this.bg});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final c = fg ?? p.primaryDark;
    return Material(
      color: bg ?? Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: 44,
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: bg == null ? Border.all(color: p.border, width: 1.5) : null),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (icon != null) ...[Icon(icon, size: 19, color: c), const SizedBox(width: 6)],
            Text(label, style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 14)),
          ]),
        ),
      ),
    );
  }
}

class Pill extends StatelessWidget {
  final String text;
  final Color bg, fg;
  const Pill(this.text, this.bg, this.fg, {super.key});
  const Pill.ok(this.text, {super.key}) : bg = okBg, fg = okFg;
  const Pill.no(this.text, {super.key}) : bg = noBg, fg = noFg;
  const Pill.low(this.text, {super.key}) : bg = loBg, fg = loFg;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
        child: Text(text, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
      );
}

/// Rounded gradient header used on home/settings style screens.
class HeroHeader extends StatelessWidget {
  final Widget child;
  const HeroHeader({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [context.pal.primary, context.pal.primaryDark]),
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(34))),
        padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 12, 20, 22),
        child: DefaultTextStyle.merge(style: const TextStyle(color: Colors.white), child: child),
      );
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
        child: Row(children: [
          Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16))),
          ?trailing,
        ]),
      );
}

class Muted extends StatelessWidget {
  final String text;
  final double size;
  final TextAlign? align;
  const Muted(this.text, {super.key, this.size = 13, this.align});
  @override
  Widget build(BuildContext context) =>
      Text(text, textAlign: align, style: TextStyle(color: context.pal.muted, fontSize: size, height: 1.4));
}

class Empty extends StatelessWidget {
  final IconData icon;
  final String text;
  const Empty(this.icon, this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(children: [
          Icon(icon, size: 48, color: context.pal.border),
          const SizedBox(height: 10),
          Muted(text, size: 14, align: TextAlign.center),
        ]),
      );
}

class Chip2 extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  const Chip2(this.label, {super.key, this.selected = false, this.onTap});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
        decoration: BoxDecoration(
            color: selected ? p.primaryDark : Colors.white,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: selected ? p.primaryDark : p.border, width: 1.5)),
        child: Text(label, style: TextStyle(color: selected ? Colors.white : p.muted, fontSize: 14)),
      ),
    );
  }
}

class Field extends StatelessWidget {
  final TextEditingController? controller;
  final String label;
  final IconData? icon;
  final TextInputType? keyboard;
  final int maxLines;
  final bool readOnly;
  final VoidCallback? onTap;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  const Field(this.label, {super.key, this.controller, this.icon, this.keyboard,
      this.maxLines = 1, this.readOnly = false, this.onTap, this.validator, this.onChanged});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: controller,
          keyboardType: keyboard,
          maxLines: maxLines,
          readOnly: readOnly,
          onTap: onTap,
          validator: validator,
          onChanged: onChanged,
          decoration: InputDecoration(
              labelText: label,
              prefixIcon: icon == null ? null : Icon(icon, color: context.pal.muted)),
        ),
      );
}

/// A scrollable page with a bottom-pinned primary action.
class FormPage extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final Widget? action;
  const FormPage({super.key, required this.title, required this.children, this.action});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600))),
        body: ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 110), children: children),
        bottomNavigationBar: action == null
            ? null
            : SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(18, 8, 18, 14), child: action)),
      );
}

/// Pill-shaped bottom bar matching the mockups.
class BottomBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  final List<(IconData, String)> items;
  const BottomBar({super.key, required this.index, required this.onTap, required this.items});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        height: 68,
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            boxShadow: [BoxShadow(color: p.primaryDark.withValues(alpha: .16), blurRadius: 30, offset: const Offset(0, 10))]),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          for (var i = 0; i < items.length; i++)
            InkWell(
              onTap: () => onTap(i),
              borderRadius: BorderRadius.circular(16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                      color: i == index ? p.soft : Colors.transparent,
                      borderRadius: BorderRadius.circular(14)),
                  child: Icon(items[i].$1, color: i == index ? p.primaryDark : p.muted.withValues(alpha: .7)),
                ),
                Text(items[i].$2,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: i == index ? FontWeight.w600 : FontWeight.w400,
                        color: i == index ? p.primaryDark : p.muted.withValues(alpha: .8))),
              ]),
            ),
        ]),
      ),
    );
  }
}

Future<bool> confirm(BuildContext c, String msg, {String yes = 'হ্যাঁ'}) async =>
    await showDialog<bool>(
        context: c,
        builder: (_) => AlertDialog(
              content: Text(msg),
              actions: [
                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('না')),
                TextButton(onPressed: () => Navigator.pop(c, true), child: Text(yes)),
              ],
            )) ??
    false;

/// Runs [load] on every rebuild (screens rebuild when AppState notifies) and
/// keeps showing the previous data while the new query is in flight.
class Q<T> extends StatelessWidget {
  final Future<T> Function() load;
  final Widget Function(BuildContext, T) builder;
  const Q({super.key, required this.load, required this.builder});
  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: load(),
        builder: (c, s) {
          if (s.hasData) return builder(c, s.data as T);
          if (s.hasError) return Padding(padding: const EdgeInsets.all(24), child: Text('ত্রুটি: ${s.error}'));
          return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
        },
      );
}
