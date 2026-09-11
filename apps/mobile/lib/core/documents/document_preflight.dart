import 'document_engine.dart';

// 打开文件时会先复制出一份 App 自有的工作副本，所以这里的上限约束的是「复制多大的
// 文件到设备存储」。具体结构仍会在编辑器真正解析文件时验证。
const maxPdfBytes = 50 * 1024 * 1024;
const maxDocxBytes = 10 * 1024 * 1024;

/// 只凭文件名和大小做的预检。
///
/// PDF 会再检查文件签名；DOCX 会在内部编辑器中解析 OOXML。
DocumentPreflightResult preflightByMetadata({
  required String fileName,
  required int byteSize,
  required bool hasLocalPath,
}) {
  final lower = fileName.toLowerCase();
  if (!hasLocalPath) {
    return const DocumentPreflightResult(
      kind: DocumentKind.unsupported,
      access: DocumentAccess.unavailable,
      title: '需要设备上的文件',
      message: '只能打开这台设备上的文件。网页版可以继续看材料清单，但不会上传或改动这个文件。',
    );
  }
  if (lower.endsWith('.pdf')) {
    if (byteSize > maxPdfBytes) {
      // 打不开就要禁用按钮：措辞说「打不开」而按钮还能按，是更糟的谎。
      return const DocumentPreflightResult(
        kind: DocumentKind.pdf,
        access: DocumentAccess.unavailable,
        title: 'PDF 太大',
        message: '超过 50 MB 的 PDF 这一版打不开。原件不会有任何改动，仍然可以导出。',
      );
    }
    return const DocumentPreflightResult(
      kind: DocumentKind.pdf,
      access: DocumentAccess.editable,
      title: '可以编辑',
      message: '会复制一份安全副本后打开；原件始终不动。',
    );
  }
  if (lower.endsWith('.docx')) {
    if (byteSize > maxDocxBytes) {
      return const DocumentPreflightResult(
        kind: DocumentKind.docx,
        access: DocumentAccess.unavailable,
        title: 'Word 文档太大',
        message: '超过 10 MB 的 Word 文档这一版打不开，但你仍然可以保留和导出原件。',
      );
    }
    return const DocumentPreflightResult(
      kind: DocumentKind.docx,
      access: DocumentAccess.editable,
      title: '可以简单编辑',
      message: '可修改普通段落文字或在末尾添加内容。复杂排版建议继续用手机上的 Word 类应用。',
    );
  }
  if (lower.endsWith('.doc')) {
    return const DocumentPreflightResult(
      kind: DocumentKind.legacyDoc,
      access: DocumentAccess.readOnly,
      title: '可以查看',
      message: '旧版 .doc 交给手机上能打开它的应用查看。这个版本不做格式转换。',
    );
  }
  return const DocumentPreflightResult(
    kind: DocumentKind.unsupported,
    access: DocumentAccess.unavailable,
    title: '暂不支持这种格式',
    message: '文件不会被修改，也不会被上传。',
  );
}
