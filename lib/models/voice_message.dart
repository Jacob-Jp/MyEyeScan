enum AlertLevel { info, warning, critical }

class VoiceMessage {
  final AlertLevel level;
  final List<String> messages;

  VoiceMessage({
    required this.level,
    required this.messages,
  });
}
