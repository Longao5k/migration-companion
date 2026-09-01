import 'document_engine.dart';

// 打开文件时会先复制出一份 App 自有的工作副本，所以这里的上限约束的是「复制多大的
// 文件到设备存储」。是否真的可编辑仍要由 document_sdk 对文件逐份 probe；只看
// 扩展名和大小不能承诺编辑能力。
const maxPdfBytes = 50 * 1024 * 1024;
const maxDocxBytes = 10 * 1024 * 1024;

/// 只凭文件名和大小做的预检。
///
/// 这里不会仅凭元数据返回 [DocumentAccess.editable]。原生 PDF 引擎会在此之后调用
/// 自研 SDK 的 `probe`，再按这一个文件的 capability 决定 editable/readOnly。
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
      title: '等待兼容性检查',
      message: '会先检查这份 PDF 支持哪些编辑能力，再复制副本打开；原件始终不动。',
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
