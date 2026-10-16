enum RetrievalMode {
  hybrid,
  semanticOnly,
  lexicalOnly,
}

class GenerationSettings {
  final double temperature;
  final double topP;
  final int contextWindow;
  final int maxTokens;
  final String systemPrompt;
  final bool useGpuAcceleration;
  final RetrievalMode retrievalMode;
  final int ragTopK;

  const GenerationSettings({
    this.temperature = 0.7,
    this.topP = 0.9,
    this.contextWindow = 4096,
    this.maxTokens = 1024,
    this.systemPrompt =
        'You are Sovereign AI, an intelligent, private, and completely offline assistant running locally on this machine.',
    this.useGpuAcceleration = true,
    this.retrievalMode = RetrievalMode.hybrid,
    this.ragTopK = 4,
  });

  GenerationSettings copyWith({
    double? temperature,
    double? topP,
    int? contextWindow,
    int? maxTokens,
    String? systemPrompt,
    bool? useGpuAcceleration,
    RetrievalMode? retrievalMode,
    int? ragTopK,
  }) {
    return GenerationSettings(
      temperature: temperature ?? this.temperature,
      topP: topP ?? this.topP,
      contextWindow: contextWindow ?? this.contextWindow,
      maxTokens: maxTokens ?? this.maxTokens,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      useGpuAcceleration: useGpuAcceleration ?? this.useGpuAcceleration,
      retrievalMode: retrievalMode ?? this.retrievalMode,
      ragTopK: ragTopK ?? this.ragTopK,
    );
  }

  Map<String, dynamic> toJson() => {
    'temperature': temperature,
    'topP': topP,
    'contextWindow': contextWindow,
    'maxTokens': maxTokens,
    'systemPrompt': systemPrompt,
    'useGpuAcceleration': useGpuAcceleration,
    'retrievalMode': retrievalMode.name,
    'ragTopK': ragTopK,
  };

  factory GenerationSettings.fromJson(Map<String, dynamic> json) {
    final rawRetrieval = json['retrievalMode'] as String?;
    final mode = RetrievalMode.values.firstWhere(
      (m) => m.name == rawRetrieval,
      orElse: () => RetrievalMode.hybrid,
    );

    return GenerationSettings(
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.7,
      topP: (json['topP'] as num?)?.toDouble() ?? 0.9,
      contextWindow: (json['contextWindow'] as num?)?.toInt() ?? 4096,
      maxTokens: (json['maxTokens'] as num?)?.toInt() ?? 1024,
      systemPrompt:
          json['systemPrompt'] as String? ??
          'You are Sovereign AI, an intelligent, private, and completely offline assistant running locally on this machine.',
      useGpuAcceleration: json['useGpuAcceleration'] as bool? ?? true,
      retrievalMode: mode,
      ragTopK: (json['ragTopK'] as num?)?.toInt() ?? 4,
    );
  }
}
