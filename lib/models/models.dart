class FileModel {
  final String file;
  final String url;
  final String caption;

  FileModel({required this.file, required this.url, required this.caption});

  factory FileModel.fromJson(Map<String, dynamic> json) {
    return FileModel(
      file: json['file'],
      url: json['url'],
      caption: json['caption'],
    );
  }
}
