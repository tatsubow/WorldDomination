import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

// 滞在ステータスの定義
enum VisitStatus {
  none,    // 未踏（白）
  visited, // 行った（オレンジ）
  stayed,  // 泊まった（赤）
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Travel Map',
      debugShowCheckedModeBanner: false, // 右上の帯を消す
      theme: ThemeData(
        useMaterial3: true,
        // アプリ全体の背景色（海の色として使用）
        scaffoldBackgroundColor: const Color(0xFFA3CCFF),
      ),
      home: const MapScreen(),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // ポリゴンデータ
  List<Polygon> _countryPolygons = [];
  List<Polygon> _statePolygons = [];

  // 表示制御フラグ（高速化のため）
  bool _showStates = false; // 現在「州」を表示しているか？
  final double _zoomThreshold = 5.0; // 切り替えの境界線

  // ユーザーの旅行データ（国名や州名をキーにする）
  final Map<String, VisitStatus> _userTravelData = {
    'Japan': VisitStatus.stayed,     // 日本：宿泊
    'United States': VisitStatus.visited, // アメリカ：訪問
    'California': VisitStatus.stayed, // カリフォルニア：宿泊
    'Tokyo': VisitStatus.stayed,      // 東京：宿泊
    'France': VisitStatus.none,       // フランス：未踏
  };

  @override
  void initState() {
    super.initState();
    // 起動後にデータを読み込む
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMapData();
    });
  }

  Future<void> _loadMapData() async {
    try {
      // JSONファイルの読み込み
      final countryString = await rootBundle.loadString('assets/countries.json');
      final stateString = await rootBundle.loadString('assets/states_provinces.json');

      // 非同期でパース処理（データ量が多いと少し時間がかかるため）
      final countryPolys = await _parseGeoJson(countryString, isState: false);
      final statePolys = await _parseGeoJson(stateString, isState: true);

      if (mounted) {
        setState(() {
          _countryPolygons = countryPolys;
          _statePolygons = statePolys;
        });
      }
    } catch (e) {
      debugPrint('Error loading Map Data: $e');
    }
  }

  // GeoJSON解析処理
  Future<List<Polygon>> _parseGeoJson(String jsonString, {required bool isState}) async {
    // 重い処理なのでFutureとして実行
    final Map<String, dynamic> jsonResult = jsonDecode(jsonString);
    final List<Polygon> polygons = [];

    for (var feature in jsonResult['features']) {
      final geometry = feature['geometry'];
      final properties = feature['properties'];

      // GeoJSONのプロパティから名前を取得
      // ※お手持ちのJSONに合わせてキー ('name', 'ADMIN', 'NAME_1'など) を調整してください
      final String name = properties['name'] ?? properties['ADMIN'] ?? 'Unknown';

      // 色の決定
      final status = _userTravelData[name] ?? VisitStatus.none;
      final Color fillColor = _getFillColor(status);
      final Color borderColor = Colors.grey.withOpacity(0.8);

      if (geometry == null) continue;

      if (geometry['type'] == 'Polygon') {
        polygons.add(_createPolygon(geometry['coordinates'], fillColor, borderColor));
      } else if (geometry['type'] == 'MultiPolygon') {
        for (var coords in geometry['coordinates']) {
          polygons.add(_createPolygon(coords, fillColor, borderColor));
        }
      }
    }
    return polygons;
  }

  // ステータスに応じた色を返す
  Color _getFillColor(VisitStatus status) {
    switch (status) {
      case VisitStatus.stayed:
        return Colors.red;
      case VisitStatus.visited:
        return Colors.orange;
      case VisitStatus.none:
      default:
        return Colors.white;
    }
  }

  // ポリゴン作成ヘルパー
  Polygon _createPolygon(List<dynamic> coords, Color color, Color borderColor) {
    // GeoJSONのリング座標を取得
    final List<dynamic> ring = coords[0];
    
    // 座標変換 [lon, lat] -> LatLng(lat, lon)
    final points = ring.map((p) {
      return LatLng(p[1].toDouble(), p[0].toDouble());
    }).toList();

    return Polygon(
      points: points,
      color: color,             // 塗りつぶしの色
      borderColor: borderColor, // 枠線の色
      borderStrokeWidth: 0.5,   // 枠線の太さ（細い方が綺麗）
      // isFilled: true,        // ← 削除済み（v8以降不要）
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Travel Map'),
        backgroundColor: Colors.white.withOpacity(0.8),
      ),
      // Scaffoldの背景色が「海」の色になります
      body: FlutterMap(
        options: MapOptions(
          initialCenter: const LatLng(35.6895, 139.6917), // 東京
          initialZoom: 3.0,
          minZoom: 2.0,
          maxZoom: 10.0,
          // 【高速化ポイント】
          // ズームが変わるたびにsetStateするのではなく、
          // 「国⇔州」の境界をまたいだ時だけ再描画する
          onPositionChanged: (camera, hasGesture) {
            final bool shouldShowStates = camera.zoom >= _zoomThreshold;
            
            // フラグが変わった時だけ setState する（これが軽量化のキモ）
            if (_showStates != shouldShowStates) {
              setState(() {
                _showStates = shouldShowStates;
              });
              debugPrint("Switched layer. Show States: $_showStates");
            }
          },
        ),
        children: [
          // ポリゴンレイヤー（シンプル化のためTileLayerは削除済み）
          PolygonLayer(
            // カリング（画面外を描画しない）を有効化
            polygonCulling: true, 
            polygons: _showStates ? _statePolygons : _countryPolygons,
          ),
        ],
      ),
    );
  }
}