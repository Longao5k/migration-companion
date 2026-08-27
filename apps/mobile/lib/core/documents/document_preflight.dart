import 'document_engine.dart';

const maxPdfBytes = 50 * 1024 * 1024;
const maxDocxBytes = 10 * 1024 * 1024;

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
      title: '需要设备本地文件',
      message: '当前编辑器只能处理设备文件。网页端可继续查看材料清单，但不会上传或修改这个文件。',
    );
  }
  if (lower.endsWith('.pdf')) {
    if (byteSize > maxPdfBytes) {
      return const DocumentPreflightResult(
        kind: DocumentKind.pdf,
        access: DocumentAccess.readOnly,
        title: 'PDF 超出首发编辑范围',
        message: '超过 50 MB 的 PDF 默认只读。原件不会被覆盖。',
      );
    }
    return const DocumentPreflightResult(
      kind: DocumentKind.pdf,
      access: DocumentAccess.editable,
      title: '可创建 PDF 编辑副本',
      message: '将先复制到应用工作区，再用评估引擎打开；任何编辑都不会覆盖所选原件。',
    );
  }
  if (lower.endsWith('.docx')) {
    return DocumentPreflightResult(
      kind: DocumentKind.docx,
      access: byteSize <= maxDocxBytes
          ? DocumentAccess.editable
          : DocumentAccess.readOnly,
      title: byteSize <= maxDocxBytes ? '可进入 DOCX 兼容检查' : 'DOCX 默认只读',
      message: byteSize <= maxDocxBytes
          ? '简单 DOCX 可进入试用编辑会话；复杂结构会转为只读且保留原件。'
          : '超过 10 MB 的 DOCX 不进入首发编辑范围，仍可保留和导出原件。',
    );
  }
  if (lower.endsWith('.doc')) {
    return const DocumentPreflightResult(
      kind: DocumentKind.legacyDoc,
      access: DocumentAccess.readOnly,
      title: '旧版 DOC 只读',
      message: '不会直接编辑旧版 DOC；后续可明确创建 DOCX 转换副本。',
    );
  }
  return const DocumentPreflightResult(
    kind: DocumentKind.unsupported,
    access: DocumentAccess.unavailable,
    title: '暂不支持此格式',
    message: '文件不会被修改或上传。',
  );
}
