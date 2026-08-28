/**
 * 云文件上传开关。
 *
 * 第一阶段初期只做本机存储：材料文件留在用户设备上，服务端不接收新的云文件。
 * 等付费云存储上线时，用户文件会放到澳洲区域的 AWS S3，而不是产品服务器本机。
 *
 * 关闭时只拦截**新增上传**。既有云文件的下载、删除和分享保持可用——
 * 冻结规则要求任何情况下用户都能取回和删除自己的文件，不能用关闭功能把数据锁住。
 */
export function cloudFileUploadsEnabled() {
  return process.env.CLOUD_FILES_ENABLED !== 'false';
}

export const cloudFilesDisabledMessage =
  '云文件上传尚未开放：当前版本的材料文件只保存在你的设备上。' +
  '云存储将在澳洲区域上线后开放，届时你可以逐个文件选择是否上传。';
