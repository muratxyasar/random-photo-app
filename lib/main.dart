import 'dart:math';
import 'package:flutter/material.dart';

void main() {
  runApp(const RandomPhotoApp());
}

class RandomPhotoApp extends StatelessWidget {
  const RandomPhotoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Random Photo App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const RandomPhotoPage(),
    );
  }
}

class RandomPhotoPage extends StatefulWidget {
  const RandomPhotoPage({super.key});

  @override
  State<RandomPhotoPage> createState() => _RandomPhotoPageState();
}

class _RandomPhotoPageState extends State<RandomPhotoPage> {
  int _randomSeed = 0;
  String _searchQuery = '';
  bool _isLoading = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _refreshPhoto();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Arama metnini URL-safe hale getir
  String _encodeQuery(String query) {
    // Boşlukları + ile değiştir, lowercase yap
    return query.trim().replaceAll(' ', '+').toLowerCase();
  }

  String _getPhotoUrl() {
    if (_searchQuery.isEmpty) {
      return 'https://picsum.photos/800/600?random=$_randomSeed&t=${DateTime.now().millisecondsSinceEpoch}';
    }
    // Loremflickr kullan
    return 'https://loremflickr.com/800/600/${_encodeQuery(_searchQuery)}?random=$_randomSeed&t=${DateTime.now().millisecondsSinceEpoch}';
  }

  void _searchPhoto(String query) {
    if (query.isEmpty) {
      _refreshPhoto();
      return;
    }

    setState(() {
      _searchQuery = query;
      _randomSeed = Random().nextInt(10000);
    });
  }

  void _refreshPhoto() {
    setState(() {
      _randomSeed = Random().nextInt(10000);
      _searchQuery = '';
      _searchController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rastgele Fotoğraf'),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Resim ara (ör: kedi, doğa, şehir)',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            _refreshPhoto();
                            setState(() {});
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (value) {
                  setState(() {});
                },
                onSubmitted: (value) {
                  if (value.isNotEmpty) {
                    _searchPhoto(value);
                  }
                },
              ),
            ),
            Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.network(
                _getPhotoUrl(),
                width: 300,
                height: 400,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return SizedBox(
                    width: 300,
                    height: 400,
                    child: Center(
                      child: CircularProgressIndicator(
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded /
                                loadingProgress.expectedTotalBytes!
                            : null,
                      ),
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return const SizedBox(
                    width: 300,
                    height: 400,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline, size: 48),
                          SizedBox(height: 12),
                          Text(
                            'Resimlerde bulunamadı\nFarklı bir arama dene',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _searchQuery.isNotEmpty
                  ? 'Arama: $_searchQuery'
                  : 'Yeni fotoğraf için butona basın',
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _refreshPhoto,
        tooltip: 'Yenile',
        label: const Text('Rastgele'),
        icon: const Icon(Icons.refresh),
      ),
    );
  }
}
