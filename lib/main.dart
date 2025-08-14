import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';

void main() => runApp(const KasirApp());

class KasirApp extends StatelessWidget {
  const KasirApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kasir Sabil',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// ===== API SERVICE =====
class ApiService {
  // GANTI sesuai lokasi api.php Anda
  static const String baseUrl = 'http://localhost/kasir_sabil/api.php';

  static Future<Map<String, dynamic>> _get(
    String path, [
    Map<String, String>? params,
  ]) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: params);
    final res = await http.get(uri);
    if (res.statusCode != 200) throw Exception('GET $path gagal: ${res.body}');
    return _parseJsonResponse(res.body);
  }

  static Future<Map<String, dynamic>> _send(
    String path,
    String method,
    Map body,
  ) async {
    final uri = Uri.parse('$baseUrl$path');
    late http.Response res;
    final headers = {'Content-Type': 'application/json'};
    final payload = jsonEncode(body);

    try {
      switch (method) {
        case 'POST':
          res = await http.post(uri, headers: headers, body: payload);
          break;
        case 'PUT':
          res = await http.put(uri, headers: headers, body: payload);
          break;
        case 'DELETE':
          res = await http.delete(uri, headers: headers, body: payload);
          break;
        default:
          throw Exception('Method tidak didukung');
      }

      if (res.statusCode >= 400) {
        throw Exception('HTTP ${res.statusCode}: ${res.body}');
      }

      return _parseJsonResponse(res.body);
    } catch (e) {
      throw Exception('Error saat mengirim data: $e');
    }
  }

  // Helper function untuk parsing JSON response dengan error handling
  static Map<String, dynamic> _parseJsonResponse(String responseBody) {
    try {
      // Bersihkan response dari warning PHP dan karakter tidak perlu
      String cleanedResponse = responseBody
          .replaceAllMapped(
            RegExp(r'<b>Warning<\/b>:.+?<br \/>\n?', caseSensitive: false),
            (match) => '',
          )
          .trim();

      // Jika setelah dibersihkan kosong, kembalikan response original
      if (cleanedResponse.isEmpty) {
        cleanedResponse = responseBody.trim();
      }

      // Parse JSON
      final result = jsonDecode(cleanedResponse) as Map<String, dynamic>;

      // Jika ada warning tapi response JSON valid, bisa ditambahkan log
      if (responseBody != cleanedResponse) {
        debugPrint('Warning PHP ditemukan dan dihilangkan');
      }

      return result;
    } catch (e) {
      throw Exception(
          'Gagal parsing JSON: $e\nOriginal Response: $responseBody');
    }
  }

  // Dashboard
  static Future<Map<String, dynamic>> dashboard() =>
      _get('', {'dashboard': '1'});

  // Barang list
  static Future<Map<String, dynamic>> listBarang({
    String search = '',
    int page = 1,
    int limit = 10,
  }) =>
      _get('/barang', {'search': search, 'page': '$page', 'limit': '$limit'});

  static Future<Map<String, dynamic>> createBarang(Map body) =>
      _send('/barang', 'POST', body);

  static Future<Map<String, dynamic>> updateBarang(int id, Map body) =>
      _send('/barang/$id', 'PUT', body);

  static Future<Map<String, dynamic>> deleteBarang(int id) =>
      _send('/barang/$id', 'DELETE', {});

  static Future<Map<String, dynamic>> tambahStok(int id, int jumlah) =>
      _send('/barang/$id/tambah-stok', 'POST', {'jumlah': jumlah});

  // Transaksi
  static Future<Map<String, dynamic>> buatTransaksi(
    List<Map<String, dynamic>> items,
    double totalBayar,
  ) =>
      _send('/transaksi', 'POST', {'items': items, 'total_bayar': totalBayar});
}

// ... (kode lainnya tetap sama, termasuk rupiah(), HomePage, DashboardPage, BarangPage, KasirPage, dll)

String rupiah(num v) {
  final f = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp',
    decimalDigits: 0,
  );
  return f.format(v);
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _index = 0;
  final _pages = const [DashboardPage(), BarangPage(), KasirPage()];
  final _titles = const ['Dashboard', 'Manajemen Barang', 'Kasir'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_titles[_index])),
      body: _pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Barang',
          ),
          NavigationDestination(
            icon: Icon(Icons.point_of_sale_outlined),
            selectedIcon: Icon(Icons.point_of_sale),
            label: 'Kasir',
          ),
        ],
      ),
    );
  }
}

// ===== DASHBOARD =====
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late Future<Map<String, dynamic>> fut;
  @override
  void initState() {
    super.initState();
    fut = ApiService.dashboard();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        setState(() => fut = ApiService.dashboard());
        await fut;
      },
      child: FutureBuilder(
        future: fut,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done)
            return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
          final data = snap.data as Map<String, dynamic>;
          final total = (data['total_penjualan_hari_ini'] ?? 0) as num;
          final trx = (data['jumlah_transaksi_hari_ini'] ?? 0) as int;
          final kurang = List<Map<String, dynamic>>.from(
            data['stok_kurang_dari_10'] ?? [],
          );
          final top3 = List<Map<String, dynamic>>.from(
            data['top3_barang'] ?? [],
          );
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _StatCard(
                    title: 'Total Hari Ini',
                    value: rupiah(total),
                    icon: Icons.payments,
                  ),
                  _StatCard(
                    title: 'Jumlah Transaksi',
                    value: '$trx',
                    icon: Icons.receipt_long,
                  ),
                  _StatCard(
                    title: 'Stok < 10',
                    value: '${kurang.length} item',
                    icon: Icons.warning_amber,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Barang stok < 10',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: kurang
                      .map(
                        (e) => ListTile(
                          title: Text(e['nama'].toString()),
                          trailing: Text('Stok: ${e['stok']}'),
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '3 Barang Terlaris',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: top3
                      .map(
                        (e) => ListTile(
                          title: Text(e['nama'].toString()),
                          trailing: Text('Terjual: ${e['total_terjual']}'),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
  });
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 320,
      child: Card(
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, size: 40),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 6),
                    Text(value, style: Theme.of(context).textTheme.titleLarge),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===== MANAJEMEN BARANG =====
class BarangPage extends StatefulWidget {
  const BarangPage({super.key});
  @override
  State<BarangPage> createState() => _BarangPageState();
}

class _BarangPageState extends State<BarangPage> {
  String search = '';
  int page = 1;
  int limit = 10;
  int total = 0;
  List<Map<String, dynamic>> data = [];
  final nameC = TextEditingController();
  final priceC = TextEditingController();
  final stockC = TextEditingController();

  Future<void> load() async {
    final res = await ApiService.listBarang(
      search: search,
      page: page,
      limit: limit,
    );
    setState(() {
      data = List<Map<String, dynamic>>.from(res['data']);
      total = res['total'] as int;
    });
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  Widget build(BuildContext context) {
    final totalPages = (total / limit).ceil().clamp(1, 9999);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Cari barang...',
                  ),
                  onChanged: (v) {
                    search = v;
                    page = 1;
                    load();
                  },
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: () => _showCreateDialog(context),
                icon: const Icon(Icons.add),
                label: const Text('Tambah'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Card(
              child: data.isEmpty
                  ? const Center(child: Text('Data kosong'))
                  : ListView.separated(
                      itemCount: data.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final b = data[i];
                        return ListTile(
                          title: Text(b['nama'].toString()),
                          subtitle: Text(
                            'Stok: ${b['stok']} • Harga: ' +
                                rupiah(double.tryParse(b['harga'].toString()) ??
                                    0),
                          ),
                          trailing: Wrap(
                            spacing: 8,
                            children: [
                              IconButton(
                                onPressed: () => _showTambahStok(context, b),
                                icon: const Icon(Icons.add_box_outlined),
                                tooltip: 'Tambah stok',
                              ),
                              IconButton(
                                onPressed: () => _showEditDialog(context, b),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                onPressed: () => _hapus(b['id'] as int),
                                icon: const Icon(Icons.delete_outline),
                                color: Colors.red,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total: $total | Halaman $page / $totalPages'),
              Row(
                children: [
                  IconButton(
                    onPressed: page > 1
                        ? () {
                            setState(() => page--);
                            load();
                          }
                        : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  IconButton(
                    onPressed: page < totalPages
                        ? () {
                            setState(() => page++);
                            load();
                          }
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _hapus(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus barang?'),
        content: const Text('Tindakan ini tidak bisa dibatalkan.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ApiService.deleteBarang(id);
    load();
  }

  Future<void> _showCreateDialog(BuildContext ctx) async {
    nameC.clear();
    priceC.clear();
    stockC.text = '0';
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Tambah Barang'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameC,
                decoration: const InputDecoration(labelText: 'Nama'),
              ),
              TextField(
                controller: priceC,
                decoration: const InputDecoration(labelText: 'Harga'),
              ),
              TextField(
                controller: stockC,
                decoration: const InputDecoration(labelText: 'Stok Awal'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ApiService.createBarang({
        'nama': nameC.text,
        'harga': double.tryParse(
              priceC.text.replaceAll('.', '').replaceAll(',', '.'),
            ) ??
            0,
        'stok': int.tryParse(stockC.text) ?? 0,
      });
      load();
    }
  }

  Future<void> _showEditDialog(BuildContext ctx, Map b) async {
    nameC.text = b['nama'].toString();

    // Handle berbagai tipe data harga dengan lebih aman
    try {
      if (b['harga'] != null) {
        priceC.text = (b['harga'] as num).toInt().toString();
      } else {
        priceC.text = '0';
      }
    } catch (e) {
      priceC.text = '0';
    }

    final ok = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Edit Barang'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameC,
                decoration: const InputDecoration(labelText: 'Nama'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: priceC,
                decoration: const InputDecoration(labelText: 'Harga'),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Update'),
          ),
        ],
      ),
    );

    if (ok == true) {
      try {
        await ApiService.updateBarang(b['id'] as int, {
          'nama': nameC.text,
          'harga': int.tryParse(priceC.text) ?? 0,
        });
        load();
      } catch (e) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text('Gagal update barang: $e')),
        );
      }
    }
  }

  Future<void> _showTambahStok(BuildContext ctx, Map b) async {
    final c = TextEditingController(text: '1');
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: Text('Tambah Stok: ${b['nama']}'),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(labelText: 'Jumlah tambah'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Tambah'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ApiService.tambahStok(b['id'] as int, int.tryParse(c.text) ?? 0);
      load();
    }
  }
}

// ===== KASIR PAGE =====
class KasirPage extends StatefulWidget {
  const KasirPage({super.key});
  @override
  State<KasirPage> createState() => _KasirPageState();
}

class _KasirPageState extends State<KasirPage> {
  String search = '';
  int page = 1;
  int limit = 10;
  int total = 0;
  List<Map<String, dynamic>> catalog = [];
  final Map<int, _CartItem> cart = {};
  final bayarC = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    final res = await ApiService.listBarang(
      search: search,
      page: page,
      limit: limit,
    );
    setState(() {
      catalog = List<Map<String, dynamic>>.from(res['data']);
      total = res['total'];
    });
  }

  num get totalHarga => cart.values.fold<num>(0, (a, c) => a + c.subtotal);

  @override
  Widget build(BuildContext context) {
    final totalPages = (total / limit).ceil().clamp(1, 9999);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Cari barang...',
                  ),
                  onChanged: (v) {
                    search = v;
                    page = 1;
                    _loadCatalog();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Text('Keranjang: ${cart.length} item'),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              children: [
                // KATALOG
                Expanded(
                  child: Card(
                    child: Column(
                      children: [
                        const ListTile(title: Text('Katalog Barang')),
                        const Divider(height: 1),
                        Expanded(
                          child: ListView.separated(
                            itemCount: catalog.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            // Di dalam ListView.separated pada KasirPage
                            itemBuilder: (ctx, i) {
                              final b = catalog[i];
                              return ListTile(
                                title: Text(b['nama'].toString()),
                                subtitle: Text(
                                  'Stok: ${b['stok']} • Harga: ${rupiah(double.tryParse(b['harga'].toString()) ?? 0)}',
                                ),
                                trailing: FilledButton.icon(
                                  onPressed: () {
                                    final id = b['id'] as int;
                                    setState(() {
                                      cart.update(
                                        id,
                                        (existing) => existing.copyWith(
                                            qty: existing.qty + 1),
                                        ifAbsent: () => _CartItem(
                                          id: id,
                                          nama: b['nama'].toString(),
                                          harga: (double.tryParse(
                                                      b['harga'].toString()) ??
                                                  0)
                                              .toDouble(),
                                          qty: 1,
                                        ),
                                      );
                                    });
                                  },
                                  icon: const Icon(Icons.add_shopping_cart),
                                  label: const Text('Tambah'),
                                ),
                              );
                            },
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              onPressed: page > 1
                                  ? () {
                                      setState(() => page--);
                                      _loadCatalog();
                                    }
                                  : null,
                              icon: const Icon(Icons.chevron_left),
                            ),
                            IconButton(
                              onPressed: page < totalPages
                                  ? () {
                                      setState(() => page++);
                                      _loadCatalog();
                                    }
                                  : null,
                              icon: const Icon(Icons.chevron_right),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 12),

                // KERANJANG
                Expanded(
                  child: Card(
                    child: Column(
                      children: [
                        const ListTile(title: Text('Keranjang')),
                        const Divider(height: 1),
                        Expanded(
                          child: cart.isEmpty
                              ? const Center(child: Text('Belum ada item'))
                              : ListView(
                                  children: cart.values
                                      .map(
                                        (c) => ListTile(
                                          title: Text(c.nama),
                                          subtitle: Text(
                                            rupiah(c.harga) +
                                                ' x ${c.qty} = ' +
                                                rupiah(c.subtotal),
                                          ),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                onPressed: () {
                                                  setState(
                                                    () => c.qty = (c.qty > 1
                                                        ? c.qty - 1
                                                        : 1),
                                                  );
                                                },
                                                icon: const Icon(
                                                  Icons.remove_circle_outline,
                                                ),
                                              ),
                                              IconButton(
                                                onPressed: () {
                                                  setState(() => c.qty++);
                                                },
                                                icon: const Icon(
                                                  Icons.add_circle_outline,
                                                ),
                                              ),
                                              IconButton(
                                                onPressed: () {
                                                  setState(
                                                    () => cart.remove(c.id),
                                                  );
                                                },
                                                icon: const Icon(
                                                  Icons.delete_outline,
                                                ),
                                                color: Colors.red,
                                              ),
                                            ],
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                        ),
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text('Total: ' + rupiah(totalHarga)),
                              const SizedBox(height: 8),
                              TextField(
                                controller: bayarC,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  prefixText: 'Bayar: ',
                                  hintText: 'Masukkan nominal uang',
                                ),
                              ),
                              const SizedBox(height: 8),
                              FilledButton.icon(
                                onPressed: _prosesBayar,
                                icon: const Icon(Icons.check_circle_outline),
                                label: const Text('Proses Transaksi'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _prosesBayar() async {
    if (cart.isEmpty) {
      _snack('Keranjang kosong');
      return;
    }
    final bayar =
        double.tryParse(bayarC.text.replaceAll('.', '').replaceAll(',', '.')) ??
            0;
    final items =
        cart.values.map((c) => {'barang_id': c.id, 'jumlah': c.qty}).toList();
    try {
      final res = await ApiService.buatTransaksi(items, bayar);
      if (res['ok'] == false && res['error'] == 'Uang kurang') {
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Uang kurang'),
            content: Text(
              'Total: ' +
                  rupiah(res['total_harga']) +
                  '\nBayar: ' +
                  rupiah(res['total_bayar']),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }
      if (res['ok'] == true) {
        final kembalian = (res['kembalian'] ?? 0) as num;
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Transaksi berhasil'),
            content: Text('Kembalian: ' + rupiah(kembalian)),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Tutup'),
              ),
            ],
          ),
        );
        setState(() {
          cart.clear();
          bayarC.clear();
        });
        _loadCatalog();
      }
    } catch (e) {
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Gagal'),
          content: Text(e.toString()),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _CartItem {
  final int id;
  final String nama;
  final double harga;
  int qty;

  _CartItem({
    required this.id,
    required this.nama,
    required this.harga,
    required this.qty,
  });

  factory _CartItem.fromBarang(Map b) => _CartItem(
        id: b['id'] as int,
        nama: b['nama'].toString(),
        harga: (double.tryParse(b['harga'].toString()) ?? 0).toDouble(),
        qty: 1,
      );

  _CartItem copyWith({int? qty}) =>
      _CartItem(id: id, nama: nama, harga: harga, qty: qty ?? this.qty);

  double get subtotal => harga * qty;
}

// --- EOF ---
