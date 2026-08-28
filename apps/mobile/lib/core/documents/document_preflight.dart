import 'document_engine.dart';

// 打开文件时会先复制出一份 App 自有的工作副本，所以这里的上限约束的是「复制多大的
// 文件到设备存储」，不是编辑器能力——这一版没有编辑器。
const maxPdfBytes = 50 * 1024 * 1024;
const maxDocxBytes = 10 * 1024 * 1024;

/// 只凭文件名和大小做的预检。
///
/// 这里永远不会返回 [DocumentAccess.editable]：编辑能力随评估版文档 SDK 一并移出
/// 发布构建（ADR-011），界面不能宣称构建做不到的事。等自研或已购许可的编辑器接进来
/// 之后，再让这里重新返回 editable。
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
      access: DocumentAccess.readOnly,
      title: '可以查看',
      message: '会先复制一份副本再打开，原件不动。这个版本还不能批注或签名。',
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
      access: DocumentAccess.readOnly,
      title: '可以查看',
      message: '会交给手机上能打开 Word 的应用查看。这个版本还不能编辑。',
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
