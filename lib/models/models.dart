// lib/models/models.dart

class SettingsModel {
  final Map<String, Map<String, dynamic>> timeframes;
  final Map<String, bool> modes;
  final Map<String, bool> sessions;

  SettingsModel({
    required this.timeframes,
    required this.modes,
    required this.sessions,
  });

  factory SettingsModel.fromJson(Map<String, dynamic> json) {
    return SettingsModel(
      timeframes: Map<String, Map<String, dynamic>>.from(json['timeframes']),
      modes: Map<String, bool>.from(json['modes']),
      sessions: Map<String, bool>.from(json['sessions']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'timeframes': timeframes,
      'modes': modes,
      'sessions': sessions,
    };
  }
}

class FileModel {
  final String file;
  final String path;
  final String caption;

  FileModel({required this.file, required this.path, required this.caption});

  factory FileModel.fromJson(Map<String, dynamic> json) {
    return FileModel(
      file: json['file'],
      path: json['path'],
      caption: json['caption'],
    );
  }
}

class UserSettings {
  final Map<String, dynamic> timeframes;
  final Map<String, dynamic> modes;
  final Map<String, dynamic> sessions;

  UserSettings({required this.timeframes, required this.modes, required this.sessions});

  factory UserSettings.fromJson(Map<String, dynamic> json) {
    return UserSettings(
      timeframes: Map<String, dynamic>.from(json['timeframes']),
      modes: Map<String, dynamic>.from(json['modes']),
      sessions: Map<String, dynamic>.from(json['sessions']),
    );
  }
}
