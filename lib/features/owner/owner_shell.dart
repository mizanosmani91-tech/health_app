import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/widgets.dart';
import 'books_page.dart';
import 'owner_ctx.dart';
import 'owner_home_page.dart';
import 'owner_profile_page.dart';
import 'requests_page.dart';
import 'stock_page.dart';

class OwnerShell extends StatelessWidget {
  const OwnerShell({super.key});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (_) => OwnerCtx()..load(),
        child: const _Body(),
      );
}

class _Body extends StatefulWidget {
  const _Body();
  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  int _i = 0;
  final _history = <int>[]; // tabs visited before this one, so Back returns to the previous page
  void go(int i) {
    if (i == _i) return;
    setState(() { _history.add(_i); _i = i; });
  }

  @override
  Widget build(BuildContext context) {
    final o = context.watch<OwnerCtx>();
    if (o.pharmacy == null) {
      return Scaffold(
        body: Center(
          child: o.error == null
              ? const CircularProgressIndicator()
              : Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(o.error!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: o.load, child: const Text('আবার চেষ্টা করুন')),
                ]),
        ),
      );
    }
    return PopScope(
      canPop: _history.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _history.isNotEmpty) setState(() => _i = _history.removeLast());
      },
      child: Scaffold(
      extendBody: true,
      body: IndexedStack(index: _i, children: [OwnerHomePage(go: go), const RequestsPage(), const StockPage(), const BooksPage(), const OwnerProfilePage()]),
      bottomNavigationBar: BottomBar(index: _i, onTap: go, items: const [
        (Icons.space_dashboard, 'হোম'), (Icons.inbox, 'অনুরোধ'), (Icons.inventory_2, 'স্টক'),
        (Icons.account_balance_wallet, 'হিসাব'), (Icons.storefront, 'প্রোফাইল'),
      ]),
    ));
  }
}
