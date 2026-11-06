/**
 * 相册头像工具（Wave 6）。
 * 通过系统 PhotoViewPicker 选图（系统授权，无需申请权限）；
 * 相册 URI 仅授予临时读权限，应用重启后失效，因此复制进应用沙箱持久保存。
 * 照片头像以「file://<沙箱绝对路径>」形式存入账号 avatar 字段；emoji 头像保持原样。
 */
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { AppContextHolder } from './AppContext';
import { Logger } from './Logger';

const FILE_PREFIX = 'zhitu_avatar_';
const ALLOWED_EXTS: string[] = ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'heic'];

export class AvatarPhoto {
  /** 判断头像是否为相册照片（沙箱 file:// 路径） */
  static isPhoto(avatar: string): boolean {
    return avatar.startsWith('file://');
  }

  /**
   * 打开系统相册选择一张图片，复制进沙箱并返回 file:// 路径。
   * 用户取消返回空串；失败记录日志并返回空串。
   */
  static async pick(): Promise<string> {
    try {
      const picker = new photoAccessHelper.PhotoViewPicker();
      const opt: photoAccessHelper.PhotoSelectOptions = {
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 1
      };
      const result: photoAccessHelper.PhotoSelectResult = await picker.select(opt);
      if (!result.photoUris || result.photoUris.length === 0) {
        return '';
      }
      const srcUri = result.photoUris[0];
      const destPath = `${AppContextHolder.get().filesDir}/${FILE_PREFIX}${Date.now()}.${AvatarPhoto.guessExt(srcUri)}`;
      const src = fs.openSync(srcUri, fs.OpenMode.READ_ONLY);
      const dest = fs.openSync(destPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.copyFileSync(src.fd, dest.fd);
      } finally {
        fs.closeSync(src);
        fs.closeSync(dest);
      }
      AvatarPhoto.cleanOld(destPath);
      return `file://${destPath}`;
    } catch (err) {
      Logger.error('AvatarPhoto', `pick failed: ${JSON.stringify(err)}`);
      return '';
    }
  }

  /** 从相册 URI 推断扩展名，失败默认 jpg */
  private static guessExt(uri: string): string {
    const lower = uri.toLowerCase();
    const dot = lower.lastIndexOf('.');
    if (dot >= 0) {
      const ext = lower.substring(dot + 1);
      if (ALLOWED_EXTS.indexOf(ext) >= 0) {
        return ext;
      }
    }
    return 'jpg';
  }

  /** 删除沙箱里除当前头像外的旧文件，避免换一次头像累积一个文件 */
  private static cleanOld(keepPath: string): void {
    try {
      const filesDir = AppContextHolder.get().filesDir;
      const names = fs.listFileSync(filesDir);
      for (let i = 0; i < names.length; i++) {
        if (names[i].startsWith(FILE_PREFIX)) {
          const full = `${filesDir}/${names[i]}`;
          if (full !== keepPath) {
            try {
              fs.unlinkSync(full);
            } catch (e) {
              Logger.warn('AvatarPhoto', `unlink ${full} failed`);
            }
          }
        }
      }
    } catch (err) {
      Logger.error('AvatarPhoto', `cleanOld failed: ${JSON.stringify(err)}`);
    }
  }
}
