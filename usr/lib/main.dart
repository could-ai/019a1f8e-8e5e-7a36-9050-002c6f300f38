import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Prédiction Tours Airtel',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.red,
        scaffoldBackgroundColor: const Color(0xFFF5F5F5),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE30613),
          primary: const Color(0xFFE30613),
          secondary: const Color(0xFFC10510),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFE30613),
          foregroundColor: Colors.white,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFE30613),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            textStyle: const TextStyle(fontWeight: FontWeight.bold),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(5),
            borderSide: const BorderSide(color: Color(0xFFDDD)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(5),
            borderSide: const BorderSide(color: Color(0xFFE30613)),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        ),
      ),
      home: const PredictionPage(),
    );
  }
}

class PredictionPage extends StatefulWidget {
  const PredictionPage({super.key});

  @override
  State<PredictionPage> createState() => _PredictionPageState();
}

class _PredictionPageState extends State<PredictionPage> {
  final _previousMultiplierController = TextEditingController();
  final _previousTimeController = TextEditingController();
  String _selectedAlgorithm = 'pattern';
  String _timeLeft = '--:--';
  Timer? _roundTimer;
  Timer? _autoPredictTimer;

  PredictionResult? _predictionResult;
  List<HistoryItem> _history = [];

  final List<String> _algorithms = [
    'pattern',
    'trend',
  ];

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _startRoundTimer();
    _previousTimeController.text = DateFormat("yyyy-MM-ddTHH:mm").format(DateTime.now());
  }

  @override
  void dispose() {
    _roundTimer?.cancel();
    _autoPredictTimer?.cancel();
    _previousMultiplierController.dispose();
    _previousTimeController.dispose();
    super.dispose();
  }

  void _startRoundTimer() {
    _roundTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final now = DateTime.now();
      final seconds = now.second;
      final timeLeft = 60 - seconds;
      setState(() {
        _timeLeft = "${timeLeft.toString().padLeft(2, '0')}s";
      });
    });
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyString = prefs.getString('airtelHistory');
    if (historyString != null) {
      final List<dynamic> decodedList = jsonDecode(historyString);
      setState(() {
        _history = decodedList.map((item) => HistoryItem.fromJson(item)).toList();
      });
    }
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final String encodedData = jsonEncode(_history.map((item) => item.toJson()).toList());
    await prefs.setString('airtelHistory', encodedData);
  }

  Future<void> _clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('airtelHistory');
    setState(() {
      _history = [];
    });
  }

  void _calculatePrediction() {
    final previousMultiplier = double.tryParse(_previousMultiplierController.text);
    final previousTime = _previousTimeController.text;

    if (previousMultiplier == null || previousTime.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez remplir tous les champs')),
      );
      return;
    }

    final prediction = _generatePrediction(previousMultiplier, previousTime, _selectedAlgorithm);

    final historyItem = HistoryItem(
      timestamp: DateTime.now(),
      previousMultiplier: previousMultiplier,
      previousTime: previousTime,
      predictedMultiplier: prediction.multiplier,
      algorithm: _selectedAlgorithm,
      confidence: prediction.confidence,
    );

    setState(() {
      _predictionResult = prediction;
      _history.insert(0, historyItem);
      if (_history.length > 20) {
        _history = _history.sublist(0, 20);
      }
    });
    _saveHistory();
  }

  PredictionResult _generatePrediction(double previousMultiplier, String previousTimeStr, String algorithm) {
    final now = DateTime.now();
    final previous = DateTime.tryParse(previousTimeStr) ?? now;
    final timeDiff = now.difference(previous).inMinutes;
    final random = Random();

    double basePrediction;
    double confidence;

    switch (algorithm) {
      case 'pattern':
        if (previousMultiplier > 50) {
          basePrediction = max(1, previousMultiplier * 0.3 + random.nextDouble() * 5);
          confidence = 45;
        } else if (previousMultiplier > 20) {
          basePrediction = previousMultiplier * 0.6 + random.nextDouble() * 10;
          confidence = 60;
        } else if (previousMultiplier > 5) {
          basePrediction = previousMultiplier * 1.2 + random.nextDouble() * 8;
          confidence = 70;
        } else {
          basePrediction = previousMultiplier * 1.8 + random.nextDouble() * 15;
          confidence = 65;
        }
        break;
      case 'trend':
      default:
        final timeFactor = min(1, timeDiff / 2);
        basePrediction = previousMultiplier * (0.8 + 0.4 * random.nextDouble()) + timeFactor * 10;
        confidence = 55 + timeFactor * 20;
        break;
    }

    final finalPrediction = max(1.0, (basePrediction * 100).round() / 100);
    confidence = confidence.clamp(25, 95);

    return PredictionResult(
      multiplier: finalPrediction,
      confidence: confidence.round(),
      range: "${max(1, (finalPrediction * 0.7).round())} - ${(finalPrediction * 1.3).round()}",
      recommendation: _getRecommendation(finalPrediction, confidence),
    );
  }

  String _getRecommendation(double multiplier, double confidence) {
    if (confidence >= 70 && multiplier >= 5) {
      return "🎯 FORT - Bonne opportunité";
    } else if (confidence >= 60) {
      return "👍 MOYEN - Potentiel intéressant";
    } else if (confidence >= 45) {
      return "⚠️ FAIBLE - À considérer avec prudence";
    } else {
      return "❌ RISQUÉ - Éviter ou petit montant";
    }
  }

  void _toggleAutoPredict() {
    if (_autoPredictTimer != null && _autoPredictTimer!.isActive) {
      _autoPredictTimer?.cancel();
      setState(() {
        _autoPredictTimer = null;
      });
    } else {
      setState(() {
        _autoPredictTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
          if (_previousMultiplierController.text.isNotEmpty) {
            _calculatePrediction();
          }
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🎯 Prédiction Tours Airtel'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildInputGroup(
                label: 'Multiplicateur précédent :',
                child: TextField(
                  controller: _previousMultiplierController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    hintText: 'Ex: 23.81',
                  ),
                ),
              ),
              const SizedBox(height: 15),
              _buildInputGroup(
                label: 'Heure du tour précédent :',
                child: TextField(
                  controller: _previousTimeController,
                  readOnly: true,
                  decoration: const InputDecoration(
                    suffixIcon: Icon(Icons.calendar_today),
                  ),
                  onTap: () async {
                    // In a real app, you'd use a date time picker.
                    // For this implementation, we just update to now.
                    setState(() {
                       _previousTimeController.text = DateFormat("yyyy-MM-ddTHH:mm").format(DateTime.now());
                    });
                  },
                ),
              ),
              const SizedBox(height: 15),
              _buildInputGroup(
                label: 'Algorithme de prédiction :',
                child: DropdownButtonFormField<String>(
                  value: _selectedAlgorithm,
                  items: _algorithms.map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value[0].toUpperCase() + value.substring(1)),
                    );
                  }).toList(),
                  onChanged: (newValue) {
                    setState(() {
                      _selectedAlgorithm = newValue!;
                    });
                  },
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                icon: const Text('🔮'),
                label: const Text('Prédire le prochain tour'),
                onPressed: _calculatePrediction,
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                icon: Text(_autoPredictTimer?.isActive ?? false ? '⏹️' : '🔄'),
                label: Text(_autoPredictTimer?.isActive ?? false ? 'Arrêter Auto' : 'Prédiction Auto'),
                onPressed: _toggleAutoPredict,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _autoPredictTimer?.isActive ?? false ? Colors.grey[700] : Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: Text(
                  'Prochain tour dans: $_timeLeft',
                  style: const TextStyle(fontSize: 18, color: Color(0xFF333)),
                ),
              ),
              if (_predictionResult != null) ...[
                const SizedBox(height: 20),
                _buildPredictionResult(_predictionResult!),
              ],
              const SizedBox(height: 20),
              _buildHistorySection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputGroup({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF333)),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  Widget _buildPredictionResult(PredictionResult result) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(5),
        border: Border(
          left: BorderSide(color: Theme.of(context).colorScheme.primary, width: 4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('🎯 Prédiction du prochain tour :', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          Center(
            child: Text(
              '${result.multiplier}x',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 10),
          _buildResultRow('Confiance :', '${result.confidence}%'),
          _buildResultRow('Plage probable :', result.range),
          _buildResultRow('Recommandation :', result.recommendation),
        ],
      ),
    );
  }

  Widget _buildResultRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        children: [
          Text('$title ', style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildHistorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('📊 Historique des tours', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        _history.isEmpty
            ? const Center(child: Text('Aucun historique.'))
            : ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _history.length,
                itemBuilder: (context, index) {
                  final item = _history[index];
                  return Card(
                    color: const Color(0xFFF0F0F0),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      title: Text(
                        'Prédit: ${item.predictedMultiplier}x (Confiance: ${item.confidence}%)',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        'Précédent: ${item.previousMultiplier}x le ${DateFormat.yMd().add_Hms().format(item.timestamp)}',
                      ),
                    ),
                  );
                },
              ),
        const SizedBox(height: 10),
        if (_history.isNotEmpty)
          TextButton.icon(
            icon: const Icon(Icons.delete_outline),
            label: const Text("Effacer l'historique"),
            onPressed: _clearHistory,
            style: TextButton.styleFrom(foregroundColor: Colors.red[700]),
          ),
      ],
    );
  }
}

class PredictionResult {
  final double multiplier;
  final int confidence;
  final String range;
  final String recommendation;

  PredictionResult({
    required this.multiplier,
    required this.confidence,
    required this.range,
    required this.recommendation,
  });
}

class HistoryItem {
  final DateTime timestamp;
  final double previousMultiplier;
  final String previousTime;
  final double predictedMultiplier;
  final String algorithm;
  final int confidence;

  HistoryItem({
    required this.timestamp,
    required this.previousMultiplier,
    required this.previousTime,
    required this.predictedMultiplier,
    required this.algorithm,
    required this.confidence,
  });

  factory HistoryItem.fromJson(Map<String, dynamic> json) {
    return HistoryItem(
      timestamp: DateTime.parse(json['timestamp']),
      previousMultiplier: json['previousMultiplier'],
      previousTime: json['previousTime'],
      predictedMultiplier: json['predictedMultiplier'],
      algorithm: json['algorithm'],
      confidence: json['confidence'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'previousMultiplier': previousMultiplier,
      'previousTime': previousTime,
      'predictedMultiplier': predictedMultiplier,
      'algorithm': algorithm,
      'confidence': confidence,
    };
  }
}
